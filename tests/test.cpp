#include "certificate.hpp"
#include "reference.hpp"
#include <set>
unsigned cases=0,skipped=0;
void check_chain(const Polygon& p) {
    std::set<double> xs;
    for (const auto& q:p.points) if (!xs.insert(q[0]).second) {++skipped;return;}
    ++cases;
    try {
        const auto reference=dd::chain_reference::diagonals(p.points,p.offsets);
        dd::chain_monotone_detail::Sweep<dd::ChainSearch::Gallop> sweep(p.points,p.offsets,nullptr);
        sweep.prepare(); sweep.run(); auto actual=sweep.diagonals();
        for (auto& d:actual) if (d.first>d.second) std::swap(d.first,d.second);
        std::sort(actual.begin(),actual.end());
        require(actual==reference,"compressed diagonals differ from full-vertex reference");
        dd::ChainMonotoneStats stats;
        const auto result=dd::triangulate_chain_monotone<dd::ChainSearch::Gallop,true>(p.points,p.offsets,&stats);
        certify(p,result);
        certify(p,dd::triangulate(p.points,p.offsets));
        std::vector<std::pair<dd::Index,dd::Index>> balanced_diagonals;
        dd::ChainMonotoneStats balanced_stats;
        const auto balanced=dd::triangulate_chain_monotone<dd::ChainSearch::Walk,true,true>(
            p.points,p.offsets,&balanced_stats,&balanced_diagonals);
        certify(p,balanced);
        const auto array=dd::triangulate_chain_monotone<dd::ChainSearch::Walk,false,true,true>(p.points,p.offsets);
        require(array.triangles==balanced.triangles,"array status changes triangulation");
        certify(p,dd::triangulate_bounded(p.points,p.offsets));
        for (auto& d:balanced_diagonals) if (d.first>d.second) std::swap(d.first,d.second);
        std::sort(balanced_diagonals.begin(),balanced_diagonals.end());
        require(balanced_diagonals==reference,"balanced status changes partition diagonals");
        require(balanced_stats.advances<=p.points.size(),"balanced cursor revisits edges");
        const auto walk=dd::triangulate_chain_monotone<dd::ChainSearch::Walk>(p.points,p.offsets);
        const auto binary=dd::triangulate_chain_monotone<dd::ChainSearch::Binary>(p.points,p.offsets);
        require(walk.triangles==result.triangles && binary.triangles==result.triangles,"search mode changes triangulation");
        require(stats.advances<=p.points.size(),"cursor passed an edge more than once");
        require(stats.diagonals+1==stats.faces+p.size()-1,"wrong face count");
    } catch (const std::exception& e) {
        if (const char* path=std::getenv("CHAIN_FAILURE")) {
            std::ofstream out(path,std::ios::binary); write_value(out,std::uint64_t{1}); write_value(out,static_cast<std::uint64_t>(p.size()));
            for (unsigned r=1;r<p.offsets.size();++r) {
                write_value(out,static_cast<std::uint64_t>(p.offsets[r]-p.offsets[r-1]));
                for (auto i=p.offsets[r-1];i<p.offsets[r];++i) for (auto x:p.points[i]) write_value(out,x);
            }
        }
        throw std::runtime_error("case="+std::to_string(cases)+" n="+std::to_string(p.points.size())+": "+e.what());
    }
}
void variants(const Polygon& p) {
    check_chain(p); Polygon q=p;
    for (auto& v:q.points) v={-v[1],v[0]};
    check_chain(q);
    q=p; for (auto& v:q.points) v[0]=-v[0];
    for (unsigned r=1;r<q.offsets.size();++r) std::reverse(q.points.begin()+q.offsets[r-1],q.points.begin()+q.offsets[r]);
    check_chain(q);
}
void check_cursors() {
    using namespace dd::chain_monotone_detail;
    for (bool forward:{true,false}) for (bool wrap:{true,false}) for (unsigned length:{1u,2u,4u,8u,64u,1000u}) {
        std::vector<dd::Point> p(length+7);
        Chain c{wrap?(forward?length+3:3):(forward?2:length+2),length,2,length+5,0,forward};
        for (unsigned i=0;i<=length;++i) p[vertex(c,i)]={double(i),double(i%3)};
        auto walk=c,binary=c,gallop=c;
        std::vector<double> queries{0.0,0.25,0.5,1.0,1.0,1.25,2.0,double(length)/2,double(length)};
        std::sort(queries.begin(),queries.end());
        for (double x:queries) {
            if (x>length) continue;
            const auto a=seek<dd::ChainSearch::Binary>(binary,x,p);
            const auto b=seek<dd::ChainSearch::Walk>(walk,x,p),d=seek<dd::ChainSearch::Gallop>(gallop,x,p);
            require(a==b && a==d,"finger search differs"); c.finger=a;
        }
    }
}
void check_fan_topology() {
    // Many diagonals share one endpoint: this exercises the second possible
    // quadratic cost independently of the sweep-status data structure.
    for (unsigned n:{16u,128u,4096u}) {
        Polygon p; p.offsets={0,n};
        for (unsigned i=0;i<n;++i) p.points.push_back({double(i),double(i)*i});
        std::vector<dd::Index> marks(n); std::iota(marks.begin(),marks.end(),0);
        std::vector<std::pair<dd::Index,dd::Index>> diagonals;
        for (unsigned i=2;i+1<n;++i) diagonals.emplace_back(0,i);
        for (bool reverse:{false,true}) {
            if (reverse) std::reverse(diagonals.begin(),diagonals.end());
            dd::chain_monotone_detail::Faces faces(p.points,p.offsets,marks);
            faces.build_sorted(diagonals); certify(p,faces.run());
        }
    }
}
void check_array_status() {
    dd::chain_monotone_detail::ArrayStatus tree;
    constexpr unsigned n=257;
    tree.reserve(4*n);
    std::set<dd::Index> live;
    std::mt19937 rng(56273);
    std::vector<dd::Index> keys(n); std::iota(keys.begin(),keys.end(),0);
    for (unsigned round=0;round<8;++round) {
        std::shuffle(keys.begin(),keys.end(),rng);
        for (auto key:keys) {
            if (round%2==0) { tree.insert(key,std::less<dd::Index>{}); live.insert(key); }
            else { tree.erase(key); live.erase(key); }
            for (unsigned q=0;q<=n;++q) {
                auto it=live.lower_bound(q);
                const auto expected=it==live.begin()?dd::chain_monotone_detail::none:*--it;
                require(tree.below([&](dd::Index id){return id<q;})==expected,"array AVL predecessor mismatch");
            }
        }
    }
}
int main(int argc,char** argv) {

    try {
        check_array_status(); check_cursors(); check_fan_topology(); std::mt19937 rng(15152026);
        for (unsigned holes=0;holes<=20;++holes) for (unsigned repeat=0;repeat<20;++repeat) {
            Polygon p; p.offsets.push_back(0); ring(p,radial(4+repeat%17,15,15,80,false,rng),repeat);
            for (unsigned h=0;h<holes;++h) ring(p,radial(3+(repeat+h)%6,10*(h%5),10*(h/5),2,true,rng),repeat+h);
            variants(p);
        }
        for (unsigned n:{3u,10u,64u,128u,256u,1024u,4096u}) {
            Polygon p; p.offsets.push_back(0); ring(p,radial(n,0,0,20,false,rng),n/3); variants(p);
        }
        // Exactly representable shears retain long collinear boundary runs.
        for (unsigned holes=1;holes<=20;++holes) {
            Polygon p; p.offsets.push_back(0);
            ring(p,{{-10,-10},{20,-10},{50,-10},{50,20},{50,50},{20,50},{-10,50},{-10,20}},holes);
            for (unsigned h=0;h<holes;++h) {
                const double x=10*(h%5),y=10*(h/5);
                ring(p,{{x,y},{x,y+3},{x+3,y+3},{x+3,y}},h);
            }
            for (auto& q:p.points) q[0]+=q[1]/1024;
            variants(p);
        }
        for (unsigned length:{8u,128u,2048u}) {
            Polygon p; p.offsets.push_back(0); std::vector<dd::Point> boundary{{-1,0}};
            for (unsigned i=0;i<length;++i) boundary.push_back({i+0.125,-3+0.1*std::sin(double(i))});
            boundary.push_back({double(length+1),0});
            for (unsigned i=length;i-- >0;) boundary.push_back({i+0.375,3+0.1*std::cos(double(i))});
            ring(p,boundary,0); variants(p);
        }
        for (unsigned holes:{8u,64u,256u}) {
            Polygon p; p.offsets.push_back(0); const double top=3*holes+10;
            ring(p,{{-10,-10},{10,-10},{10,top},{-10,top}},0);
            for (unsigned h=0;h<holes;++h) {
                const double y=3*h;
                ring(p,{{0,y},{0,y+1},{2,y+1},{2,y}},0);
            }
            for (auto& q:p.points) q[0]+=q[1]/(1024*holes);
            check_chain(p);
        }
        for (const auto& o:std::vector<std::vector<dd::Index>>{{},{0},{0,3},{1,3,6},{0,2,6},{0,6,5},{0,3,7}}) {
            bool rejected=false;
            try { (void)dd::triangulate_chain_monotone(std::vector<dd::Point>(6),o); }
            catch (const std::invalid_argument&) { rejected=true; }
            require(rejected,"invalid shape accepted");
        }
        std::cout<<"generated="<<cases<<" equal_x_skipped="<<skipped<<'\n';
        for (int arg=1;arg<argc;++arg) {
            const auto corpus=load(argv[arg]); unsigned tested=0;
            for (const auto& p:corpus) if (p.points.size()<=4096) {check_chain(p);++tested;}
            std::cout<<argv[arg]<<" checked="<<tested<<'\n';
        }
        std::cout<<"PASS cases="<<cases<<" equal_x_skipped="<<skipped<<'\n';
    } catch (const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
