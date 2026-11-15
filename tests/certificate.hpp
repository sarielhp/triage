#pragma once
#include "corpus.hpp"
#include <map>
#include <random>
void require(bool condition,const char* message) {
    if (!condition) throw std::runtime_error(message);
}
// Independent certificate: exact positive triangles and equality of oriented
// boundary chains imply geometric coverage, not merely equal total areas.
void certify(const Polygon& p,const dd::Result& mesh) {
    using Rat=boost::multiprecision::cpp_rational;
    require(mesh.triangles.size()==p.points.size()+2*(p.size()-1)-2,"wrong triangle count");
    std::map<std::pair<dd::Index,dd::Index>,int> boundary;
    auto edge=[&](dd::Index a,dd::Index b,int sign) {
        if (a<b) boundary[{a,b}]+=sign; else boundary[{b,a}]-=sign;
    };
    for (const auto& t:mesh.triangles) {
        for (auto id:t) require(id<p.points.size(),"nonoriginal triangle index");
        const auto& a=p.points[t[0]]; const auto& b=p.points[t[1]]; const auto& c=p.points[t[2]];
        require((Rat(b[0])-Rat(a[0]))*(Rat(c[1])-Rat(a[1]))-
                (Rat(b[1])-Rat(a[1]))*(Rat(c[0])-Rat(a[0]))>0,"nonpositive triangle");
        for (unsigned i=0;i<3;++i) edge(t[i],t[(i+1)%3],1);
    }
    for (std::size_t r=1;r<p.offsets.size();++r)
        for (auto i=p.offsets[r-1];i<p.offsets[r];++i)
            edge(i,i+1==p.offsets[r]?p.offsets[r-1]:i+1,-1);
    for (const auto& entry:boundary) require(entry.second==0,"oriented boundary mismatch");
}
void ring(Polygon& p,const std::vector<dd::Point>& points,unsigned shift) {
    for (unsigned i=0;i<points.size();++i) p.points.push_back(points[(i+shift)%points.size()]);
    p.offsets.push_back(static_cast<dd::Index>(p.points.size()));
}
std::vector<dd::Point> radial(unsigned n,double x,double y,double radius,bool clockwise,std::mt19937& rng) {
    std::uniform_real_distribution<double> noise(0.6,1.0);
    std::vector<dd::Point> result;
    for (unsigned i=0;i<n;++i) {
        const double angle=(clockwise?-1:1)*2*std::acos(-1.0)*(i+0.137)/n;
        const double r=radius*noise(rng);
        result.push_back({x+r*std::cos(angle),y+r*std::sin(angle)});
    }
    return result;
}
