// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include "MixedInputSegmenter.h"

#include <set>
#include <string>

#include "gtest/gtest.h"

namespace McBopomofo {
namespace {

using Boundary = MixedInputSegmenter::Boundary;
using Kind = MixedInputSegmenter::SegmentKind;
using Segment = MixedInputSegmenter::Segment;

class MixedInputSegmenterTest : public ::testing::Test {
 protected:
  MixedInputSegmenter makeSegmenter() {
    return MixedInputSegmenter([this](const std::string& reading) {
      return readings.contains(reading);
    });
  }

  std::set<std::string> readings = {"ㄋㄧˇ", "ㄨㄛ", "ㄐㄧˋ", "ㄇˇ"};
};

TEST_F(MixedInputSegmenterTest, KeepsInvalidBopomofoAsLiteral) {
  auto result = makeSegmenter().segment("call", Boundary::kEnter);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "call", ""}}));
}

TEST_F(MixedInputSegmenterTest, FindsLongestChineseSuffix) {
  auto result = makeSegmenter().segment("callsu3");
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "call", ""},
                                  {Kind::kChinese, "su3", "ㄋㄧˇ"}}));
}

TEST_F(MixedInputSegmenterTest, SpaceCompletesFirstTone) {
  auto result = makeSegmenter().segment("ji", Boundary::kSpace);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kChinese, "ji", "ㄨㄛ"}}));
}

TEST_F(MixedInputSegmenterTest, EnterDoesNotCompleteFirstTone) {
  auto result = makeSegmenter().segment("ji", Boundary::kEnter);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "ji", ""}}));
}

TEST_F(MixedInputSegmenterTest, RejectsComponentOverwrite) {
  auto result = makeSegmenter().segment("call3");
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "call3", ""}}));
}

TEST_F(MixedInputSegmenterTest, ProtectsEmailRetroactively) {
  auto beforeMarker = makeSegmenter().segment("a3");
  EXPECT_EQ(beforeMarker.segments,
            (std::vector<Segment>{{Kind::kChinese, "a3", "ㄇˇ"}}));

  auto afterMarker = makeSegmenter().segment("a3@example.com");
  EXPECT_TRUE(afterMarker.protectedAscii);
  EXPECT_EQ(afterMarker.segments,
            (std::vector<Segment>{{Kind::kLiteral, "a3@example.com", ""}}));
}

TEST_F(MixedInputSegmenterTest, ProtectsUrlAndProgramTokens) {
  for (const std::string& raw : {"https://example.com/a3", "x86_64",
                                 "sha256", "C++", "foo_bar"}) {
    SCOPED_TRACE(raw);
    auto result = makeSegmenter().segment(raw);
    EXPECT_TRUE(result.protectedAscii);
    EXPECT_EQ(result.segments,
              (std::vector<Segment>{{Kind::kLiteral, raw, ""}}));
  }
}

TEST_F(MixedInputSegmenterTest, DoesNotSplitSingleKeySuffixFromAsciiPrefix) {
  auto result = makeSegmenter().segment("version4");
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "version4", ""}}));
}

TEST_F(MixedInputSegmenterTest, IsDeterministic) {
  auto segmenter = makeSegmenter();
  auto expected = segmenter.segment("callsu3");
  for (size_t index = 0; index < 100; ++index) {
    EXPECT_EQ(segmenter.segment("callsu3"), expected);
  }
}

TEST_F(MixedInputSegmenterTest, SupportsOnlyPrintableAscii) {
  EXPECT_TRUE(MixedInputSegmenter::IsSupportedAscii('a'));
  EXPECT_TRUE(MixedInputSegmenter::IsSupportedAscii('~'));
  EXPECT_FALSE(MixedInputSegmenter::IsSupportedAscii('\n'));
  EXPECT_FALSE(MixedInputSegmenter::IsSupportedAscii(
      static_cast<char>(0xc3)));
}

}  // namespace
}  // namespace McBopomofo
