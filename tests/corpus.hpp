#pragma once
#include <triage/triage.hpp>
#include <fstream>
#include <iostream>
#include <string>
namespace dd = triage;
struct RingView {
    using value_type = dd::Point;
    const dd::Point* points;
    std::size_t count;
    std::size_t size() const { return count; }
    const dd::Point& operator[](std::size_t i) const { return points[i]; }
};
// Both algorithms read exactly the same coordinate allocation. Earcut sees
// non-owning ring views; neither timed call copies or converts input storage.
struct Polygon {
    std::vector<dd::Point> points;
    std::vector<dd::Index> offsets;
    std::size_t size() const { return offsets.size() - 1; }
    bool empty() const { return size() == 0; }
    RingView operator[](std::size_t i) const {
        return {points.data() + offsets[i], offsets[i + 1] - offsets[i]};
    }
};
using Corpus = std::vector<Polygon>;


template<class T> T read_value(std::istream& input) {
    T value{};
    input.read(reinterpret_cast<char*>(&value), sizeof value);
    if (!input) throw std::runtime_error("truncated input");
    return value;
}
template<class T> void write_value(std::ostream& output, const T& value) {
    output.write(reinterpret_cast<const char*>(&value), sizeof value);
}
Corpus load(const char* path) {
    std::ifstream input(path, std::ios::binary);
    const auto count = read_value<std::uint64_t>(input);
    if (count > 1000000) throw std::runtime_error("invalid polygon count");
    Corpus corpus(count);
    for (auto& polygon : corpus) {
        const auto rings = read_value<std::uint64_t>(input);
        if (rings == 0 || rings > 1000000) throw std::runtime_error("invalid ring count");
        polygon.offsets.push_back(0);
        for (std::size_t r = 0; r < rings; ++r) {
            const auto n = read_value<std::uint64_t>(input);
            if (n < 3 || n + polygon.points.size() >= (std::uint64_t{1} << 31))
                throw std::runtime_error("invalid vertex count");
            const auto start = polygon.points.size();
            polygon.points.resize(start + n);
            input.read(reinterpret_cast<char*>(polygon.points.data() + start), n * sizeof(dd::Point));
            if (!input) throw std::runtime_error("truncated coordinates");
            polygon.offsets.push_back(static_cast<dd::Index>(polygon.points.size()));
        }
    }
    if (input.peek() != std::char_traits<char>::eof()) throw std::runtime_error("trailing input bytes");
    return corpus;
}

