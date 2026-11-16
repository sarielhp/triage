#include "../tests/certificate.hpp"
#include "earcut.hpp"
#include <chrono>
#include <iomanip>
#include <numeric>

volatile std::uint64_t checksum_sink=0;
std::uint64_t consume(const std::vector<dd::Triangle>& ts) {
    asm volatile("" : : "g"(ts.data()), "g"(ts.size()) : "memory");
    return 3*ts.size()+(ts.empty()?0:ts.front()[0]+ts.back()[2]);
}
std::uint64_t consume(const std::vector<dd::Index>& ts) {
    asm volatile("" : : "g"(ts.data()), "g"(ts.size()) : "memory");
    return ts.size()+(ts.empty()?0:ts.front()+ts.back());
}
template<unsigned Mode> double measure(const Corpus& corpus,std::size_t reps) {
    std::uint64_t checksum=0;
    const auto start=std::chrono::steady_clock::now();
    for (std::size_t r=0;r<reps;++r) for (const auto& p:corpus) {
        if constexpr(Mode==4) checksum+=consume(dd::triangulate_dispatch<true,false>(p.points,p.offsets).triangles);
        else if constexpr(Mode==3) checksum+=consume(dd::triangulate_dispatch<true,true>(p.points,p.offsets).triangles);
        else if constexpr(Mode==1) checksum+=consume(mapbox::earcut<dd::Index>(p));
        else if constexpr(Mode==2) checksum+=consume(dd::triangulate_bounded(p.points,p.offsets).triangles);
        else checksum+=consume(dd::triangulate(p.points,p.offsets).triangles);
    }
    const double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    checksum_sink=checksum_sink+checksum;
    return elapsed/reps;
}
double measure(const Corpus& corpus,unsigned mode,std::size_t reps) {
    if (mode==4) return measure<4>(corpus,reps);
    if (mode==3) return measure<3>(corpus,reps);
    if (mode==2) return measure<2>(corpus,reps);
    return mode==0?measure<0>(corpus,reps):measure<1>(corpus,reps);
}
void benchmark(const Corpus& corpus,const char* path,bool strategies=false,bool triage_only=false,bool status=false) {
    const char* names[]={"triage-cpp","earcut","triage-bounded-cpp","triage-array-cpp","triage-legacy-bounded-cpp"};
    const unsigned modes=strategies?3:2;
    const auto method=[&](unsigned slot) { return status?4-slot:(triage_only?2*slot:slot); };
    std::ofstream out(path);
    if (!out) throw std::runtime_error("cannot open timing output");
    out<<"method,sample,repetitions,seconds_per_corpus\n"<<std::setprecision(17);
    double fastest=1e100,slowest=0;
    for (unsigned m=0;m<modes;++m) {
        measure(corpus,method(m),1); const double pilot=measure(corpus,method(m),1);
        fastest=std::min(fastest,pilot);slowest=std::max(slowest,pilot);
    }
    const auto reps=static_cast<std::size_t>(std::clamp(std::min(std::ceil(0.02/fastest),
        std::max(1.0,std::floor(0.1/slowest))),1.0,100000.0));
    std::vector<double> samples[3];
    for (unsigned round=0;round<12;++round) for (unsigned j=0;j<modes;++j) {
        const auto mode=(round+j)%modes;
        const double time=measure(corpus,method(mode),reps);
        samples[mode].push_back(time);
        out<<names[method(mode)]<<','<<round+1<<','<<reps<<','<<time<<'\n';
    }
    for (unsigned m=0;m<modes;++m) {
        auto& times=samples[m]; std::sort(times.begin(),times.end());
        std::cout<<names[method(m)]<<" polygons="<<corpus.size()<<" median_ms="<<500*(times[5]+times[6])<<'\n';
    }
    if (!out) throw std::runtime_error("timing write failed");
}
void dump(const Corpus& corpus,const char* path,bool bounded=false,bool array=false) {
    std::ofstream out(path,std::ios::binary);
    write_value(out,std::uint64_t{0x484f4c4544554d31}); write_value(out,std::uint64_t(corpus.size()));
    for (const auto& p:corpus) {
        const auto mesh=array?dd::triangulate_dispatch<true,true>(p.points,p.offsets):
            (bounded?dd::triangulate_bounded(p.points,p.offsets):dd::triangulate(p.points,p.offsets));
        write_value(out,std::uint64_t(p.points.size()));write_value(out,std::uint64_t{0});
        write_value(out,std::uint64_t(mesh.triangles.size()));
        for (const auto& t:mesh.triangles) for (const auto i:t) write_value(out,i);
    }
    if (!out) throw std::runtime_error("mesh write failed");
}
int main(int argc,char** argv) {
    try {
        if (argc!=4) throw std::runtime_error("usage: triage_bench bench|bench-strategies|bench-triage|bench-status|dump|dump-bounded|dump-array|validate|validate-bounded|validate-earcut INPUT OUTPUT");
        const auto corpus=load(argv[2]);
        const std::string action=argv[1];
        if (action=="bench") benchmark(corpus,argv[3]);
        else if(action=="bench-strategies") benchmark(corpus,argv[3],true);
        else if(action=="bench-triage") benchmark(corpus,argv[3],false,true);
        else if(action=="bench-status") benchmark(corpus,argv[3],false,false,true);
        else if(action=="dump") dump(corpus,argv[3]);
        else if(action=="dump-bounded") dump(corpus,argv[3],true);
        else if(action=="dump-array") dump(corpus,argv[3],true,true);
        else if(action=="validate-earcut") {
            for (const auto& p:corpus) {
                const auto indices=mapbox::earcut<dd::Index>(p);
                require(indices.size()%3==0,"invalid Earcut output length");
                dd::Result mesh;
                for (std::size_t i=0;i<indices.size();i+=3)
                    mesh.triangles.push_back({indices[i],indices[i+1],indices[i+2]});
                certify(p,mesh);
            }
            std::cout<<"PASS Earcut exact coverage: "<<corpus.size()<<" domains\n";
        }
        else if(action=="validate" || action=="validate-bounded") {
            for (const auto& p:corpus) certify(p,action=="validate"?
                dd::triangulate(p.points,p.offsets):dd::triangulate_bounded(p.points,p.offsets));
            std::cout<<"PASS exact coverage: "<<corpus.size()<<" domains\n";
        } else throw std::runtime_error("unknown action");
    } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
