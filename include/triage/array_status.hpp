#pragma once
#include "small.hpp"

namespace triage::chain_monotone_detail {
// Adapted from BasicCompGeometry 0.6.1's SweepTriangulation.jl AVL design
// (Copyright (c) 2026 Sariel Har-Peled, MIT; see LICENSE).
// Keys are interval IDs. Deletion uses handles, with no geometric comparisons.
// There are at most two insertions per extremum; reserve once for that bound.
class ArrayStatus {
    static constexpr Index nil=std::numeric_limits<Index>::max();
    std::vector<Index> left_,right_,parent_,height_,key_,slot_;
    Index root_=nil,allocated_=0;
    Index height(Index i) const { return i==nil?0:height_[i]; }
    void update(Index i) { height_[i]=1+std::max(height(left_[i]),height(right_[i])); }
    void replace(Index p,Index old,Index fresh) {
        if (p==nil) root_=fresh;
        else if (left_[p]==old) left_[p]=fresh;
        else right_[p]=fresh;
        if (fresh!=nil) parent_[fresh]=p;
    }
    Index rotate_left(Index x) {
        const Index y=right_[x],p=parent_[x],b=left_[y];
        right_[x]=b; if (b!=nil) parent_[b]=x;
        left_[y]=x; parent_[x]=y; replace(p,x,y);
        update(x); update(y); return y;
    }
    Index rotate_right(Index y) {
        const Index x=left_[y],p=parent_[y],b=right_[x];
        left_[y]=b; if (b!=nil) parent_[b]=y;
        right_[x]=y; parent_[y]=x; replace(p,y,x);
        update(y); update(x); return x;
    }
    void rebalance(Index u) {
        while (u!=nil) {
            update(u);
            const int delta=int(height(left_[u]))-int(height(right_[u]));
            if (delta>1) {
                const Index l=left_[u];
                if (height(left_[l])<height(right_[l])) rotate_left(l);
                u=rotate_right(u);
            } else if (delta < -1) {
                const Index r=right_[u];
                if (height(right_[r])<height(left_[r])) rotate_right(r);
                u=rotate_left(u);
            }
            u=parent_[u];
        }
    }
public:
    std::size_t capacity_bytes() const {
        return (left_.capacity()+right_.capacity()+parent_.capacity()+height_.capacity()+
            key_.capacity()+slot_.capacity())*sizeof(Index);
    }
    void reserve(std::size_t capacity) {
        if (capacity>=nil) throw std::length_error("status capacity exceeds index range");
        left_.assign(capacity,nil); right_.assign(capacity,nil);
        parent_.assign(capacity,nil); height_.assign(capacity,0);
        key_.assign(capacity,nil); slot_.assign(capacity,nil);
        root_=nil; allocated_=0;
    }
    template<class Less> void insert(Index id,Less less) {
        if (id>=slot_.size() || allocated_>=key_.size()) throw std::length_error("status capacity exhausted");
        if (slot_[id]!=nil) throw std::runtime_error("duplicate status boundary");
        const Index fresh=allocated_++;
        key_[fresh]=id; slot_[id]=fresh; height_[fresh]=1;
        Index cur=root_,par=nil; bool right=false;
        while (cur!=nil) {
            par=cur; right=!less(id,key_[cur]);
            cur=right?right_[cur]:left_[cur];
        }
        parent_[fresh]=par;
        if (par==nil) root_=fresh;
        else if (right) right_[par]=fresh;
        else left_[par]=fresh;
        rebalance(par);
    }
    void erase(Index id) {
        Index z=slot_.at(id);
        if (z==nil) throw std::runtime_error("missing status boundary");
        slot_[id]=nil;
        if (left_[z]!=nil && right_[z]!=nil) {
            Index y=right_[z];
            while (left_[y]!=nil) y=left_[y];
            key_[z]=key_[y]; slot_[key_[y]]=z; z=y;
        }
        const Index child=left_[z]!=nil?left_[z]:right_[z],p=parent_[z];
        replace(p,z,child); rebalance(p);
    }
    template<class Below> Index below(Below predicate) const {
        Index cur=root_,best=nil;
        while (cur!=nil) {
            if (predicate(key_[cur])) { best=key_[cur]; cur=right_[cur]; }
            else cur=left_[cur];
        }
        return best;
    }
};
} // namespace triage::chain_monotone_detail
