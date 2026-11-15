#pragma once
// Test-only full-vertex reference. It deliberately retains one sorted event
// per vertex and an edge status, independently of compressed chain intervals.
#include <triage/small.hpp>
#include <numeric>
namespace triage::chain_reference {
inline std::vector<std::pair<Index,Index>> diagonals(const std::vector<Point>& p,const std::vector<Index>& o) {
    const Index n=p.size();
    std::vector<Index> prev(n),next(n),order(n),helper(n),active,position(n);
    std::vector<bool> merge(n,false);
    std::vector<std::pair<Index,Index>> result;
    for (unsigned r=1;r<o.size();++r) for (Index v=o[r-1];v<o[r];++v) {
        prev[v]=v==o[r-1]?o[r]-1:v-1; next[v]=v+1==o[r]?o[r-1]:v+1;
    }
    auto turn=[&](Index a,Index b,Index c){return orient_original(p[a],p[b],p[c]);};
    auto add=[&](Index a,Index b){result.emplace_back(std::min(a,b),std::max(a,b));};
    auto finish=[&](Index e,Index v){if (merge[helper[e]]) add(v,helper[e]);};
    auto insert=[&](Index v){position[v]=active.size(); active.push_back(v); helper[v]=v;};
    auto erase=[&](Index v){const Index slot=position[v],last=active.back(); active.pop_back(); if (slot<active.size()) {active[slot]=last;position[last]=slot;}};
    auto below=[&](Index v) {
        Index best=std::numeric_limits<Index>::max();
        for (const Index e:active) if (turn(e,next[e],v)>0 &&
            (best==std::numeric_limits<Index>::max() || (p[best][0]<p[e][0]?turn(best,next[best],e)>0:turn(e,next[e],best)<0))) best=e;
        if (best==std::numeric_limits<Index>::max()) throw std::runtime_error("reference missing predecessor");
        return best;
    };
    std::iota(order.begin(),order.end(),0);
    std::sort(order.begin(),order.end(),[&](Index a,Index b){return p[a][0]<p[b][0];});
    for (Index k=1;k<n;++k) if (p[order[k-1]][0]==p[order[k]][0]) throw std::invalid_argument("reference needs distinct x");
    for (Index v:order) {
        const Index a=prev[v],b=next[v]; const bool pa=p[v][0]<p[a][0],pb=p[v][0]<p[b][0],convex=turn(a,v,b)>0;
        if (pa && pb) {
            if (!convex) {const Index e=below(v); add(v,helper[e]); helper[e]=v;} insert(v);
        } else if (!pa && !pb) {
            merge[v]=!convex; finish(a,v); erase(a);
            if (!convex) {const Index e=below(v); finish(e,v); helper[e]=v;}
        } else if (pb) {finish(a,v); erase(a); insert(v);}
        else {const Index e=below(v); finish(e,v); helper[e]=v;}
    }
    std::sort(result.begin(),result.end()); return result;
}
}
