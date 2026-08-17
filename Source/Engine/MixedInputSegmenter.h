// Copyright (c) 2026 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifndef SRC_ENGINE_MIXEDINPUTSEGMENTER_H_
#define SRC_ENGINE_MIXEDINPUTSEGMENTER_H_

#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace McBopomofo {

class MixedInputSegmenter {
 public:
  enum class Boundary {
    kNone,
    kSpace,
    kEnter,
  };

  enum class SegmentKind {
    kLiteral,
    kChinese,
  };

  struct Segment {
    SegmentKind kind;
    std::string raw;
    std::string reading;

    bool operator==(const Segment&) const = default;
  };

  struct Result {
    std::vector<Segment> segments;
    bool protectedAscii = false;

    bool operator==(const Result&) const = default;
  };

  using HasUnigrams = std::function<bool(const std::string&)>;

  explicit MixedInputSegmenter(HasUnigrams hasUnigrams);

  [[nodiscard]] Result segment(std::string_view raw,
                               Boundary boundary = Boundary::kNone) const;

  [[nodiscard]] static bool IsSupportedAscii(char key);
  [[nodiscard]] static bool HasStructuralAsciiEvidence(std::string_view raw);

 private:
  [[nodiscard]] std::optional<std::string> strictReading(
      std::string_view keys, bool completesFirstTone) const;
  static void appendLiteral(std::vector<Segment>& segments,
                            std::string_view raw);

  HasUnigrams hasUnigrams_;
};

}  // namespace McBopomofo

#endif  // SRC_ENGINE_MIXEDINPUTSEGMENTER_H_
