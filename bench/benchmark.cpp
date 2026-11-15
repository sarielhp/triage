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
template<bool Earcut> double measure(const Corpus& corpus,std::size_t reps) {
    std::uint64_t checksum=0;
    const auto start=std::chrono::steady_clock::now();
    for (std::size_t r=0;r<reps;++r) for (const auto& p:corpus) {
        if constexpr(Earcut) checksum+=consume(mapbox::earcut<dd::Index>(p));
        else checksum+=consume(dd::triangulate(p.points,p.offsets).triangles);
    }
    const double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
    checksum_sink=checksum_sink+checksum;
    return elapsed/reps;
}
double measure(const Corpus& corpus,unsigned mode,std::size_t reps) {
    return mode==0?measure<false>(corpus,reps):measure<true>(corpus,reps);
}
void benchmark(const Corpus& corpus,const char* path) {
    const char* names[]={"triage-cpp","earcut"};
    std::ofstream out(path);
    if (!out) throw std::runtime_error("cannot open timing output");
    out<<"method,sample,repetitions,seconds_per_corpus\n"<<std::setprecision(17);
    double fastest=1e100,slowest=0;
    for (unsigned m=0;m<2;++m) {
        measure(corpus,m,1); const double pilot=measure(corpus,m,1);
        fastest=std::min(fastest,pilot);slowest=std::max(slowest,pilot);
    }
    const auto reps=static_cast<std::size_t>(std::clamp(std::min(std::ceil(0.02/fastest),
        std::max(1.0,std::floor(0.1/slowest))),1.0,100000.0));
    std::vector<double> samples[2];
    for (unsigned round=0;round<12;++round) for (unsigned j=0;j<2;++j) {
        const auto mode=(round+j)%2;
        const double time=measure(corpus,mode,reps);
        samples[mode].push_back(time);
        out<<names[mode]<<','<<round+1<<','<<reps<<','<<time<<'\n';
    }
    for (unsigned m=0;m<2;++m) {
        auto& times=samples[m]; std::sort(times.begin(),times.end());
        std::cout<<names[m]<<" polygons="<<corpus.size()<<" median_ms="<<500*(times[5]+times[6])<<'\n';
    }
    if (!out) throw std::runtime_error("timing write failed");
}
void dump(const Corpus& corpus,const char* path) {
    std::ofstream out(path,std::ios::binary);
    write_value(out,std::uint64_t{0x484f4c4544554d31}); write_value(out,std::uint64_t(corpus.size()));
    for (const auto& p:corpus) {
        const auto mesh=dd::triangulate(p.points,p.offsets);
        write_value(out,std::uint64_t(p.points.size()));write_value(out,std::uint64_t{0});
        write_value(out,std::uint64_t(mesh.triangles.size()));
        for (const auto& t:mesh.triangles) for (const auto i:t) write_value(out,i);
    }
    if (!out) throw std::runtime_error("mesh write failed");
}
int main(int argc,char** argv) {
    try {
        if (argc!=4) throw std::runtime_error("usage: triage_bench bench|dump|validate INPUT OUTPUT");
        const auto corpus=load(argv[2]);
        const std::string action=argv[1];
        if (action=="bench") benchmark(corpus,argv[3]);
        else if(action=="dump") dump(corpus,argv[3]);
        else if(action=="validate") {
            for (const auto& p:corpus) certify(p,dd::triangulate(p.points,p.offsets));
            std::cout<<"PASS exact coverage: "<<corpus.size()<<" domains\n";
        } else throw std::runtime_error("unknown action");
    } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
