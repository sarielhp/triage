#pragma once
#include "small.hpp"
#include <chrono>
#include <numeric>
#include <utility>

namespace triage {
enum class ChainSearch { Binary, Walk, Gallop };
struct ChainMonotoneStats {
    std::uint64_t queries=0,advances=0,search_tests=0,status_visits=0;
    std::size_t chains=0,diagonals=0,faces=0,max_active=0,tape_nodes=0,workspace_capacity_bytes=0;
    double prepare_seconds=0,sweep_seconds=0,topology_seconds=0,triangulate_seconds=0;
};
namespace chain_monotone_detail {
constexpr Index none=std::numeric_limits<Index>::max();
struct Chain { Index first,length,begin,end,finger=0; bool forward; };
inline Index vertex(const Chain& c,Index offset) {
    std::int64_t v=std::int64_t(c.first)+(c.forward?std::int64_t(offset):-std::int64_t(offset));
    if (v<c.begin) v+=c.end-c.begin;
    if (v>=c.end) v-=c.end-c.begin;
    return static_cast<Index>(v);
}
// Strict predecessor: at an edge endpoint x, return the edge ending there.
// Each original chain owns its cursor. Reading its successor does not move it.
template<ChainSearch Mode,bool Measure=false>
Index seek(Chain& c,double x,const std::vector<Point>& p,ChainMonotoneStats* stats=nullptr) {
    const Index old=c.finger;
    if constexpr (Measure) ++stats->queries;
    auto passed=[&](Index k) {
        if constexpr (Measure) ++stats->search_tests;
        return p[vertex(c,k)][0]<x;
    };
    Index lo=Mode==ChainSearch::Binary?0:c.finger,hi=c.length;
    if constexpr (Mode==ChainSearch::Walk) {
        while (lo+1<hi && passed(lo+1)) ++lo;
    } else if constexpr (Mode==ChainSearch::Gallop) {
        for (unsigned i=0;i<3 && lo+1<hi;++i) {
            if (!passed(lo+1)) { hi=lo+1; break; }
            ++lo;
        }
        Index step=1;
        while (lo+1<hi) {
            const Index q=lo+std::min(step,hi-lo);
            if (q==hi || !passed(q)) { hi=q; break; }
            lo=q; step=std::min(step,hi-lo)*2;
        }
        while (hi-lo>1) { const Index mid=lo+(hi-lo)/2; if (passed(mid)) lo=mid; else hi=mid; }
    } else {
        while (hi-lo>1) { const Index mid=lo+(hi-lo)/2; if (passed(mid)) lo=mid; else hi=mid; }
    }
    if (lo<old) throw std::runtime_error("chain cursor moved backward");
    c.finger=lo;
    if constexpr (Measure) stats->advances+=lo-old;
    return lo;
}

template<ChainSearch Mode,bool Measure=false>
class Sweep {
    const std::vector<Point>& p_;
    const std::vector<Index>& offsets_;
    ChainMonotoneStats* stats_;
    std::vector<Chain> chains_;
    struct Event { Index v,out,in; unsigned char kind; };
    std::vector<Event> events_;
    struct Interval { Index low,high,helper,first_after_merge,slot; bool pending; };
    std::vector<Interval> intervals_;
    std::vector<Index> active_,owner_;
    std::vector<std::pair<Index,Index>> diagonals_;
    Index at(Index c,Index k) const { return vertex(chains_[c],k); }
    Index predecessor(Index c,double x) { return seek<Mode,Measure>(chains_[c],x,p_,stats_); }
    int turn(Index a,Index b,Index c) const { return orient_original(p_[a],p_[b],p_[c]); }
    void add_diagonal(Index a,Index b) {
        if (a==b) throw std::runtime_error("zero diagonal");
        diagonals_.emplace_back(a,b);
    }
    Index fresh(Index low,Index high,Index helper,bool pending) {
        const Index id=intervals_.size();
        Index next=none;
        if (pending) {
            const Index a=at(low,predecessor(low,p_[helper][0])+1);
            const Index b=at(high,predecessor(high,p_[helper][0])+1);
            next=p_[a][0]<p_[b][0]?a:b;
        }
        intervals_.push_back({low,high,helper,next,static_cast<Index>(active_.size()),pending});
        active_.push_back(id); owner_[low]=owner_[high]=id;
        if constexpr (Measure) stats_->max_active=std::max(stats_->max_active,active_.size());
        return id;
    }
    void remove(Index id) {
        const Index slot=intervals_[id].slot,last=active_.back(); active_.pop_back();
        if (slot<active_.size()) { active_[slot]=last; intervals_[last].slot=slot; }
    }
    void sync(Index id,Index v) {
        auto& interval=intervals_[id]; const double x=p_[v][0];
        if (interval.pending && p_[interval.first_after_merge][0]<x) {
            add_diagonal(interval.helper,interval.first_after_merge);
            interval.helper=interval.first_after_merge; interval.pending=false;
        }
        const Index a=at(interval.low,predecessor(interval.low,x));
        const Index b=at(interval.high,predecessor(interval.high,x));
        const Index latest=p_[a][0]>p_[b][0]?a:b;
        if (p_[latest][0]>p_[interval.helper][0]) {
            if (interval.pending) throw std::runtime_error("missed pending merge");
            interval.helper=latest;
        }
    }
    void finish(Index id,Index v) {
        sync(id,v);
        if (intervals_[id].pending) add_diagonal(v,intervals_[id].helper);
    }
    Index below(Index v) {
        Index best=none,ba=none,bb=none;
        for (const Index id:active_) {
            if constexpr (Measure) ++stats_->status_visits;
            const Index c=intervals_[id].low,k=predecessor(c,p_[v][0]),a=at(c,k),b=at(c,k+1);
            if (turn(a,b,v)<=0) continue;
            if (best==none || (p_[ba][0]<p_[a][0]?turn(ba,bb,a)>0:turn(a,b,ba)<0)) {
                best=id; ba=a; bb=b;
            }
        }
        if (best==none) throw std::runtime_error("missing sweep interval");
        return best;
    }
public:
    Sweep(const std::vector<Point>& p,const std::vector<Index>& o,ChainMonotoneStats* stats)
        :p_(p),offsets_(o),stats_(stats) {}
    void prepare() {
        if (p_.size()<3 || p_.size()>=none || offsets_.size()<2 || offsets_.front()!=0 || offsets_.back()!=p_.size())
            throw std::invalid_argument("invalid chain-monotone input shape");
        for (unsigned r=1;r<offsets_.size();++r) {
            const Index begin=offsets_[r-1],end=offsets_[r];
            if (end>p_.size() || end<begin || end-begin<3) throw std::invalid_argument("invalid ring offsets");
            const Index first=events_.size();
            for (Index v=begin;v<end;++v) {
                const Index a=v==begin?end-1:v-1,b=v+1==end?begin:v+1;
                if (!std::isfinite(p_[v][0]) || !std::isfinite(p_[v][1]) || std::max(std::abs(p_[v][0]),std::abs(p_[v][1]))>=1e12)
                    throw std::invalid_argument("finite bounded coordinates required");
                if (p_[v][0]==p_[b][0]) throw std::invalid_argument("distinct x required");
                const bool pa=p_[a][0]>p_[v][0],pb=p_[b][0]>p_[v][0];
                if (pa==pb) events_.push_back({v,0,0,static_cast<unsigned char>((pa?1:3)+(turn(a,v,b)<=0))});
            }
            const Index last=events_.size(),base=chains_.size();
            if (last-first<2) throw std::invalid_argument("missing ring extrema");
            for (Index j=first;j<last;++j) {
                const Index a=events_[j].v,b=events_[j+1==last?first:j+1].v;
                const Index length=b>a?b-a:b+end-begin-a;
                const bool forward=p_[a][0]<p_[b][0];
                chains_.push_back({forward?a:b,length,begin,end,0,forward});
                events_[j].out=base+j-first;
                events_[j].in=base+(j==first?last-first-1:j-first-1);
            }
        }
        owner_.resize(chains_.size(),none);
        intervals_.reserve(events_.size()); diagonals_.reserve(events_.size()/2);
        active_.reserve(std::min<std::size_t>(events_.size(),64));
        std::sort(events_.begin(),events_.end(),[&](const Event& a,const Event& b){return p_[a.v][0]<p_[b.v][0];});
        for (unsigned i=1;i<events_.size();++i)
            if (p_[events_[i-1].v][0]==p_[events_[i].v][0]) throw std::invalid_argument("distinct extremum x required");
        if constexpr (Measure) stats_->chains=chains_.size();
    }
    void run() {
        for (const auto& e:events_) {
            const Index positive=chains_[e.out].forward?e.out:e.in;
            const Index negative=chains_[e.out].forward?e.in:e.out;
            if (e.kind==1) fresh(positive,negative,e.v,false);
            else if (e.kind==2) {
                const Index id=below(e.v); sync(id,e.v);
                const auto old=intervals_[id]; add_diagonal(e.v,old.helper); remove(id);
                fresh(old.low,negative,e.v,false); fresh(positive,old.high,e.v,false);
            } else if (e.kind==3) {
                const Index id=owner_[positive];
                if (id!=owner_[negative]) throw std::runtime_error("end interval mismatch");
                finish(id,e.v); remove(id);
            } else {
                const Index upper=owner_[positive],lower=owner_[negative];
                if (upper==lower) throw std::runtime_error("merge interval mismatch");
                finish(lower,e.v); finish(upper,e.v);
                const Index low=intervals_[lower].low,high=intervals_[upper].high;
                remove(lower); remove(upper); fresh(low,high,e.v,true);
            }
        }
        if (!active_.empty()) throw std::runtime_error("unfinished sweep");
        if constexpr (Measure) stats_->diagonals=diagonals_.size();
    }
    std::vector<Index> marks() const {
        std::vector<Index> m; m.reserve(events_.size()+2*diagonals_.size());
        for (const auto& e:events_) m.push_back(e.v);
        for (const auto& d:diagonals_) { m.push_back(d.first); m.push_back(d.second); }
        std::sort(m.begin(),m.end()); m.erase(std::unique(m.begin(),m.end()),m.end()); return m;
    }
    const auto& diagonals() const { return diagonals_; }
    const auto& chains() const { return chains_; }
    std::size_t capacity_bytes() const {
        return chains_.capacity()*sizeof(Chain)+events_.capacity()*sizeof(Event)+intervals_.capacity()*sizeof(Interval)+
            (active_.capacity()+owner_.capacity())*sizeof(Index)+diagonals_.capacity()*sizeof(diagonals_[0]);
    }
};

// Nodes delimit monotone original-boundary ranges or single diagonals.
// Only extrema and diagonal endpoints receive records; intermediate vertices
// are traversed directly in the caller's coordinate array.
class Faces {
    struct Node { Index id,prev,next,alias,ring; bool original,seen=false; };
    const std::vector<Point>& p_;
    const std::vector<Index>& offsets_;
    std::vector<Index> marks_,heads_;
    std::vector<Node> nodes_;
    struct Event { Index id; bool upper; };
    std::vector<Event> stack_;
    Result result_;
    Index next_original(Index v,Index ring) const { return v+1==offsets_[ring+1]?offsets_[ring]:v+1; }
    Index prev_original(Index v,Index ring) const { return v==offsets_[ring]?offsets_[ring+1]-1:v-1; }
    Index incoming(Index v) const {
        const auto& n=nodes_[v]; const auto& a=nodes_[n.prev];
        return a.original?prev_original(n.id,a.ring):a.id;
    }
    Index outgoing(Index v) const {
        const auto& n=nodes_[v]; return n.original?next_original(n.id,n.ring):nodes_[n.next].id;
    }
    int turn(Index a,Index b,Index c) const { return orient_original(p_[a],p_[b],p_[c]); }
    bool sector(Index v,Index q) const {
        const auto id=nodes_[v].id,a=incoming(v),b=outgoing(v);
        const int left=turn(a,id,q),right=turn(id,b,q);
        return turn(a,id,b)>=0?left>0 && right>0:left>0 || right>0;
    }
    Index occurrence(Index key,Index q) const {
        for (Index v=heads_[key];v!=none;v=nodes_[v].alias) if (sector(v,q)) return v;
        throw std::runtime_error("missing diagonal endpoint sector");
    }
    void diagonal(Index a,Index b) {
        const Index ak=std::lower_bound(marks_.begin(),marks_.end(),a)-marks_.begin();
        const Index bk=std::lower_bound(marks_.begin(),marks_.end(),b)-marks_.begin();
        const Index av=occurrence(ak,b),bv=occurrence(bk,a);
        const Index following=nodes_[av].next,previous=nodes_[bv].prev;
        const Index bc=nodes_.size(),ac=bc+1;
        nodes_.push_back({b,previous,ac,heads_[bk],nodes_[bv].ring,false,false});
        nodes_.push_back({a,bc,following,heads_[ak],nodes_[av].ring,nodes_[av].original,false});
        heads_[ak]=ac; heads_[bk]=bc;
        nodes_[av].next=bv; nodes_[av].original=false; nodes_[bv].prev=av;
        nodes_[previous].next=bc; nodes_[following].prev=ac;
    }
    struct Cursor { Index node,id; };
    void forward(Cursor& c) const {
        const auto& n=nodes_[c.node]; const Index target=nodes_[n.next].id;
        c.id=n.original?next_original(c.id,n.ring):target;
        if (c.id==target) c.node=n.next;
    }
    void backward(Cursor& c) const {
        const Index previous=nodes_[c.node].prev; const auto& n=nodes_[previous];
        c.id=n.original?prev_original(c.id,n.ring):n.id;
        if (c.id==n.id) c.node=previous;
    }
    void emit(Index a,Index b,Index c) {
        const int sign=turn(a,b,c);
        if (!sign) throw std::runtime_error("zero-area monotone triangle");
        if (sign<0) std::swap(b,c);
        result_.triangles.push_back({a,b,c});
    }
    void face(Index left,Index right) {
        const Index first=nodes_[left].id,last=nodes_[right].id;
        Cursor lower{left,first},upper{left,first}; forward(lower); backward(upper);
        auto take=[&]() -> Event {
            const bool high=lower.id==last || (upper.id!=last && p_[upper.id][0]<p_[lower.id][0]);
            const Index id=high?upper.id:lower.id;
            if (high) backward(upper); else forward(lower);
            return {id,high};
        };
        stack_.clear(); stack_.push_back({first,false}); Event previous=take(); stack_.push_back(previous);
        while (lower.id!=last || upper.id!=last) {
            const Event v=take();
            if (!(p_[previous.id][0]<p_[v.id][0])) throw std::runtime_error("nonmonotone face");
            if (v.upper!=stack_.back().upper) {
                while (stack_.size()>=2) { const auto q=stack_.back(); stack_.pop_back(); emit(v.id,q.id,stack_.back().id); }
                stack_.clear(); stack_.push_back(previous); stack_.push_back(v);
            } else {
                auto q=stack_.back(); stack_.pop_back();
                while (!stack_.empty()) {
                    const auto a=stack_.back(); const int t=turn(a.id,q.id,v.id);
                    if (!(v.upper?t<0:t>0)) break;
                    emit(a.id,q.id,v.id); q=stack_.back(); stack_.pop_back();
                }
                stack_.push_back(q); stack_.push_back(v);
            }
            previous=v;
        }
        while (stack_.size()>=2) { const auto q=stack_.back(); stack_.pop_back(); emit(last,q.id,stack_.back().id); }
    }
public:
    Faces(const std::vector<Point>& p,const std::vector<Index>& o,std::vector<Index> marks)
        :p_(p),offsets_(o),marks_(std::move(marks)) {}
    void build(const std::vector<std::pair<Index,Index>>& diagonals) {
        nodes_.reserve(marks_.size()+2*diagonals.size()); heads_.resize(marks_.size());
        Index start=0;
        for (Index r=0;r+1<offsets_.size();++r) {
            Index end=start; while (end<marks_.size() && marks_[end]<offsets_[r+1]) ++end;
            if (end-start<2) throw std::runtime_error("missing ring marks");
            for (Index i=start;i<end;++i) {
                nodes_.push_back({marks_[i],i==start?end-1:i-1,i+1==end?start:i+1,none,r,true,false}); heads_[i]=i;
            }
            start=end;
        }
        for (const auto& d:diagonals) diagonal(d.first,d.second);
    }
    Result run(ChainMonotoneStats* stats=nullptr) {
        result_.triangles.reserve(p_.size()+2*(offsets_.size()-2)-2); stack_.reserve(64);
        std::size_t faces=0;
        for (Index start=0;start<nodes_.size();++start) {
            if (nodes_[start].seen) continue;
            Index left=start,right=start,v=start;
            do {
                if (nodes_[v].seen) throw std::runtime_error("invalid face tape");
                nodes_[v].seen=true;
                if (p_[nodes_[v].id][0]<p_[nodes_[left].id][0]) left=v;
                if (p_[nodes_[right].id][0]<p_[nodes_[v].id][0]) right=v;
                v=nodes_[v].next;
            } while (v!=start);
            face(left,right); ++faces;
        }
        if (result_.triangles.size()!=p_.size()+2*(offsets_.size()-2)-2) throw std::runtime_error("wrong chain-monotone count");
        if (stats) {
            stats->faces=faces; stats->tape_nodes=nodes_.size();
            stats->workspace_capacity_bytes+=marks_.capacity()*sizeof(Index)+heads_.capacity()*sizeof(Index)+nodes_.capacity()*sizeof(Node)+stack_.capacity()*sizeof(Event);
        }
        return std::move(result_);
    }
};
}

template<ChainSearch Mode=ChainSearch::Gallop,bool Measure=false>
Result triangulate_chain_monotone(const std::vector<Point>& p,const std::vector<Index>& offsets,
    ChainMonotoneStats* stats=nullptr,std::vector<std::pair<Index,Index>>* diagonals=nullptr) {
    using Clock=std::chrono::steady_clock;
    Clock::time_point before;
    if constexpr (Measure) { if (!stats) throw std::invalid_argument("stats required"); *stats={}; before=Clock::now(); }
    chain_monotone_detail::Sweep<Mode,Measure> sweep(p,offsets,stats); sweep.prepare();
    if constexpr (Measure) { const auto now=Clock::now(); stats->prepare_seconds=std::chrono::duration<double>(now-before).count(); before=now; }
    sweep.run();
    if constexpr (Measure) { const auto now=Clock::now(); stats->sweep_seconds=std::chrono::duration<double>(now-before).count(); before=now; stats->workspace_capacity_bytes=sweep.capacity_bytes(); }
    if (diagonals) *diagonals=sweep.diagonals();
    chain_monotone_detail::Faces faces(p,offsets,sweep.marks()); faces.build(sweep.diagonals());
    if constexpr (Measure) { const auto now=Clock::now(); stats->topology_seconds=std::chrono::duration<double>(now-before).count(); before=now; }
    auto result=faces.run(Measure?stats:nullptr);
    if constexpr (Measure) stats->triangulate_seconds=std::chrono::duration<double>(Clock::now()-before).count();
    return result;
}
}
