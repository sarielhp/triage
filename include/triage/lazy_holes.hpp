#pragma once
#include "small.hpp"
#include <utility>

namespace triage {
inline constexpr unsigned lazy_holes_capacity=128;
namespace lazy_holes_detail {
// Compare signed distances of p and q to the directed line c->a. The common
// positive denominator is unnecessary. Convert original inputs before doing
// any arithmetic in the exact fallback.
[[gnu::noinline,gnu::cold]] inline int exact_height(
    const Point& a,const Point& c,const Point& p,const Point& q) {
    using R=detail::Rational;
    const R value=(R(a[0])-R(c[0]))*(R(p[1])-R(q[1]))-
                  (R(a[1])-R(c[1]))*(R(p[0])-R(q[0]));
    return value>0 ? 1 : value<0 ? -1 : 0;
}
inline int compare_height(const Point& a,const Point& c,const Point& p,const Point& q) {
    const double left=(a[0]-c[0])*(p[1]-q[1]);
    const double right=(a[1]-c[1])*(p[0]-q[0]);
    const double value=left-right;
    const double bound=8*std::numeric_limits<double>::epsilon()*(std::abs(left)+std::abs(right));
    return std::abs(value)>bound ? (value>0 ? 1:-1) : exact_height(a,c,p,q);
}

class Cutter {
    using Slot=std::uint16_t;
    struct Node { Index id; Slot prev,next; };
    const std::vector<Point>& p_;
    const std::vector<Index>& offsets_;
    std::array<Node,216> node_;
    std::array<std::uint64_t,4> reflex_{};
    std::array<std::uint64_t,2> pending_{};
    unsigned used_,words_,pending_words_,remaining_,unjoined_;

    int turn(unsigned a,unsigned b,unsigned c) const {
        return orient_original(p_[node_[a].id],p_[node_[b].id],p_[node_[c].id]);
    }
    void refresh(unsigned a) {
        const auto bit=std::uint64_t{1}<<(a%64);
        if (turn(node_[a].prev,a,node_[a].next)<=0) reflex_[a/64] |= bit;
        else reflex_[a/64] &= ~bit;
    }
    void update(unsigned a) {
        if (reflex_[a/64] & (std::uint64_t{1}<<(a%64))) refresh(a);
    }
    void prepare() {
        for (std::size_t r=1;r<offsets_.size();++r) {
            const auto begin=offsets_[r-1],end=offsets_[r];
            for (Index i=begin;i<end;++i) {
                node_[i]={i,static_cast<Slot>(i==begin ? end-1:i-1),
                            static_cast<Slot>(i+1==end ? begin:i+1)};
                if (r>1) pending_[i/64] |= std::uint64_t{1}<<(i%64);
            }
        }
        for (unsigned i=0;i<remaining_;++i) refresh(i);
    }
    struct Ear {
        Index a,b,c;
        double x0,x1,y0,y1;
    };
    Ear ear(unsigned a,unsigned b,unsigned c) const {
        const Index ia=node_[a].id,ib=node_[b].id,ic=node_[c].id;
        return {ia,ib,ic,std::min({p_[ia][0],p_[ib][0],p_[ic][0]}),
                        std::max({p_[ia][0],p_[ib][0],p_[ic][0]}),
                        std::min({p_[ia][1],p_[ib][1],p_[ic][1]}),
                        std::max({p_[ia][1],p_[ib][1],p_[ic][1]})};
    }
    bool contains(const Ear& e,Index id) const {
        const auto& q=p_[id];
        return q[0]>=e.x0 && q[0]<=e.x1 && q[1]>=e.y0 && q[1]<=e.y1 &&
               small_detail::contains(p_[e.a],p_[e.b],p_[e.c],q);
    }
    bool blocked(const Ear& e) const {
        for (unsigned w=0;w<words_;++w) {
            auto bits=reflex_[w];
            while (bits) {
                const auto id=node_[64*w+static_cast<unsigned>(__builtin_ctzll(bits))].id;
                bits &= bits-1;
                if (id!=e.a && id!=e.b && id!=e.c && contains(e,id)) return true;
            }
        }
        return false;
    }
    int blocking_hole(const Ear& e) const {
        int best=-1;
        for (unsigned w=0;w<pending_words_;++w) {
            auto bits=pending_[w];
            while (bits) {
                const unsigned id=64*w+static_cast<unsigned>(__builtin_ctzll(bits));
                bits &= bits-1;
                if (contains(e,id) && (best<0 || compare_height(p_[e.a],p_[e.c],p_[id],p_[best])>0))
                    best=static_cast<int>(id);
            }
        }
        return best;
    }
    void join(unsigned b,unsigned h) {
        const auto end_it=std::upper_bound(offsets_.begin(),offsets_.end(),h);
        const Index begin=*(end_it-1),end=*end_it;
        const Slot following=node_[b].next,previous=node_[h].prev;
        const auto hc=static_cast<Slot>(used_++),bc=static_cast<Slot>(used_++);
        node_[hc]={node_[h].id,previous,bc};
        node_[bc]={node_[b].id,hc,following};
        node_[b].next=static_cast<Slot>(h); node_[h].prev=static_cast<Slot>(b);
        node_[previous].next=hc; node_[following].prev=bc;
        words_=(used_+63)/64;
        for (Index i=begin;i<end;++i) {
            pending_[i/64] &= ~(std::uint64_t{1}<<(i%64));
            refresh(i);
        }
        refresh(b); refresh(hc); refresh(bc);
        remaining_+=end-begin+2;
        --unjoined_;
    }
public:
    Cutter(const std::vector<Point>& p,const std::vector<Index>& offsets)
        :p_(p),offsets_(offsets),used_(static_cast<unsigned>(p.size())),words_((used_+63)/64),
         pending_words_(words_),remaining_(offsets[1]),unjoined_(static_cast<unsigned>(offsets.size()-2)) {}
    bool run(Result& output) {
        prepare();
        Result result;
        result.triangles.reserve(used_+2*unjoined_-2);
        unsigned current=0,misses=0;
        while (remaining_>3 || unjoined_>0) {
            const unsigned a=node_[current].prev,c=node_[current].next;
            if (!(reflex_[current/64] & (std::uint64_t{1}<<(current%64)))) {
                const Ear e=ear(a,current,c);
                if (!blocked(e)) {
                    const int h=unjoined_ ? blocking_hole(e) : -1;
                    if (h>=0) {
                        join(current,static_cast<unsigned>(h));
                        misses=0;
                        continue;
                    }
                    if (remaining_<=3) return false; // An unjoined hole was lost.
                    result.triangles.push_back({e.a,e.b,e.c});
                    node_[a].next=static_cast<Slot>(c); node_[c].prev=static_cast<Slot>(a);
                    update(a); update(c);
                    --remaining_; misses=0; current=c;
                    continue;
                }
            }
            if (++misses>=remaining_) return false;
            current=c;
        }
        const unsigned b=node_[current].next,c=node_[b].next;
        if (turn(current,b,c)<=0) return false;
        result.triangles.push_back({node_[current].id,node_[b].id,node_[c].id});
        output=std::move(result);
        return true;
    }
};
} // namespace lazy_holes_detail

// Same strict domain contract and failure convention as the bridge-first
// helper. Join holes only when they block an otherwise valid connected ear.
inline bool try_triangulate_lazy_holes(const std::vector<Point>& points,
                                     const std::vector<Index>& offsets,Result& output) {
    if (points.size()>lazy_holes_capacity || offsets.size()<3 || offsets.front()!=0 || offsets.back()!=points.size())
        return false;
    for (std::size_t r=1;r<offsets.size();++r)
        if (offsets[r]>points.size() || offsets[r]<offsets[r-1] || offsets[r]-offsets[r-1]<3) return false;
    return lazy_holes_detail::Cutter(points,offsets).run(output);
}
} // namespace triage
