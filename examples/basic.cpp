#include <triage/triage.hpp>
#include <iostream>
int main() {
    const std::vector<triage::Point> points{{0,0},{4,0},{5,4},{1,5},
                                           {1.5,1},{2,2},{3,1}};
    const auto mesh=triage::triangulate(points,{0,4,7});
    for (const auto& t:mesh.triangles) std::cout<<t[0]<<' '<<t[1]<<' '<<t[2]<<'\n';
    return mesh.triangles.size()==7 ? 0 : 1;
}
