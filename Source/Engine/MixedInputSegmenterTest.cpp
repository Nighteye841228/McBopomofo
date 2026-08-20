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

  std::set<std::string> readings = {"ㄋㄧˇ", "ㄨㄛ", "ㄨㄛˇ", "ㄧㄡˇ", "ㄐㄧㄡˋ",
                                    "ㄅㄢˋ", "ㄉㄞˇ", "ㄉㄚˋ", "ㄓㄚˋ", "ㄚˋ",
                                    "ㄓㄚ", "ㄚ", "ㄐㄧˋ", "ㄇˇ", "ㄒㄧㄢˋ",
                                    "ㄗㄞˋ", "ㄓㄨㄥ", "ㄨㄣˊ", "ㄑㄧㄝ", "ㄧㄝ"};
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

TEST_F(MixedInputSegmenterTest, PrefersShortestChineseSuffixAfterAscii) {
  MixedInputSegmenter allReadings([](const std::string&) { return true; });
  auto isolated = allReadings.segment("su3");
  ASSERT_EQ(isolated.segments.size(), 1);
  std::string expectedReading = isolated.segments[0].reading;
  MixedInputSegmenter segmenter([&](const std::string& reading) {
    return reading == expectedReading;
  });
  auto result = segmenter.segment("callsu3");
  ASSERT_EQ(result.segments.size(), 2);
  EXPECT_EQ(result.segments[0], (Segment{Kind::kLiteral, "call", ""}));
  EXPECT_EQ(result.segments[1].kind, Kind::kChinese);
  EXPECT_EQ(result.segments[1].raw, "su3");
}

TEST_F(MixedInputSegmenterTest, SegmentsCoreMixedInputExample) {
  auto result = makeSegmenter().segment("ji3vu04y94callsu3");
  EXPECT_FALSE(result.protectedAscii);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kChinese, "ji3", "ㄨㄛˇ"},
                                  {Kind::kChinese, "vu04", "ㄒㄧㄢˋ"},
                                  {Kind::kChinese, "y94", "ㄗㄞˋ"},
                                  {Kind::kLiteral, "call", ""},
                                  {Kind::kChinese, "su3", "ㄋㄧˇ"}}));
}

TEST_F(MixedInputSegmenterTest, SpaceCompletesFirstTone) {
  auto result = makeSegmenter().segment("ji", Boundary::kSpace);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kChinese, "ji", "ㄨㄛ"}}));
}

TEST_F(MixedInputSegmenterTest, SpaceFindsFirstToneSuffixAfterAscii) {
  MixedInputSegmenter allReadings([](const std::string&) { return true; });
  auto isolated = allReadings.segment("d9", Boundary::kSpace);
  ASSERT_EQ(isolated.segments.size(), 1);
  std::string expectedReading = isolated.segments[0].reading;
  MixedInputSegmenter segmenter([&](const std::string& reading) {
    return reading == expectedReading;
  });
  auto result = segmenter.segment("interfaced9", Boundary::kSpace);
  ASSERT_EQ(result.segments.size(), 2);
  EXPECT_EQ(result.segments[0], (Segment{Kind::kLiteral, "interface", ""}));
  EXPECT_EQ(result.segments[1].kind, Kind::kChinese);
  EXPECT_EQ(result.segments[1].raw, "d9");
}

TEST_F(MixedInputSegmenterTest, PrefersConsonantLedChineseFirstToneSuffix) {
  auto result = makeSegmenter().segment("capsfu,", Boundary::kSpace);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "caps", ""},
                                  {Kind::kChinese, "fu,", "ㄑㄧㄝ"}}));
}

TEST_F(MixedInputSegmenterTest, AllowsSingleComponentSuffixBeforeTone) {
  MixedInputSegmenter allReadings([](const std::string&) { return true; });
  auto isolated = allReadings.segment("m3");
  ASSERT_EQ(isolated.segments.size(), 1);
  std::string expectedReading = isolated.segments[0].reading;
  MixedInputSegmenter segmenter([&](const std::string& reading) {
    return reading == expectedReading;
  });
  auto result = segmenter.segment("dashboardm3");
  ASSERT_EQ(result.segments.size(), 2);
  EXPECT_EQ(result.segments[0], (Segment{Kind::kLiteral, "dashboard", ""}));
  EXPECT_EQ(result.segments[1].kind, Kind::kChinese);
  EXPECT_EQ(result.segments[1].raw, "m3");
}

TEST_F(MixedInputSegmenterTest, ParsesChineseSyllablesSeparatedByFirstToneSpace) {
  auto result = makeSegmenter().segment("5j/", Boundary::kSpace);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kChinese, "5j/", "ㄓㄨㄥ"}}));

  result = makeSegmenter().segment("jp6", Boundary::kEnter);
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kChinese, "jp6", "ㄨㄣˊ"}}));
}

TEST_F(MixedInputSegmenterTest, SlashAloneIsNotStructuralAsciiEvidence) {
  EXPECT_FALSE(MixedInputSegmenter::HasStructuralAsciiEvidence("5j/"));
  EXPECT_TRUE(MixedInputSegmenter::HasStructuralAsciiEvidence(
      "https://example.com"));
}

TEST_F(MixedInputSegmenterTest, PeriodAloneIsNotStructuralAsciiEvidence) {
  EXPECT_FALSE(MixedInputSegmenter::HasStructuralAsciiEvidence("u.3"));
  EXPECT_FALSE(MixedInputSegmenter::HasStructuralAsciiEvidence("ru.4"));

  auto you = makeSegmenter().segment("u.3");
  EXPECT_EQ(you.segments,
            (std::vector<Segment>{{Kind::kChinese, "u.3", "ㄧㄡˇ"}}));
  auto jiu = makeSegmenter().segment("ru.4");
  EXPECT_EQ(jiu.segments,
            (std::vector<Segment>{{Kind::kChinese, "ru.4", "ㄐㄧㄡˋ"}}));
}

TEST_F(MixedInputSegmenterTest, DomainPeriodIsStructuralAsciiEvidence) {
  EXPECT_TRUE(MixedInputSegmenter::HasStructuralAsciiEvidence("bt4g.org"));
  EXPECT_TRUE(MixedInputSegmenter::HasStructuralAsciiEvidence("foo.bar"));
  EXPECT_FALSE(MixedInputSegmenter::HasStructuralAsciiEvidence("u.3"));
  EXPECT_FALSE(MixedInputSegmenter::HasStructuralAsciiEvidence("ru.4"));
}

TEST_F(MixedInputSegmenterTest, NumericSyllablesOverrideAsciiEvidence) {
  const std::vector<Segment> expected = {
      {Kind::kChinese, "104", "ㄅㄢˋ"},
      {Kind::kChinese, "293", "ㄉㄞˇ"},
      {Kind::kChinese, "284", "ㄉㄚˋ"},
      {Kind::kChinese, "584", "ㄓㄚˋ"},
  };
  for (const Segment& segment : expected) {
    SCOPED_TRACE(segment.raw);
    EXPECT_TRUE(MixedInputSegmenter::HasStructuralAsciiEvidence(segment.raw));
    auto result = makeSegmenter().segment(segment.raw);
    EXPECT_FALSE(result.protectedAscii);
    EXPECT_EQ(result.segments, (std::vector<Segment>{segment}));
  }
}

TEST_F(MixedInputSegmenterTest, CompleteSyllableWinsOverSharedRhyme) {
  auto fourthTone = makeSegmenter().segment("584");
  EXPECT_EQ(fourthTone.segments,
            (std::vector<Segment>{{Kind::kChinese, "584", "ㄓㄚˋ"}}));

  auto firstTone = makeSegmenter().segment("58", Boundary::kSpace);
  EXPECT_EQ(firstTone.segments,
            (std::vector<Segment>{{Kind::kChinese, "58", "ㄓㄚ"}}));
}

TEST_F(MixedInputSegmenterTest, MissingCompleteReadingDoesNotUseSharedRhyme) {
  MixedInputSegmenter rhymeOnly([](const std::string& reading) {
    return reading == "ㄚˋ";
  });
  auto result = rhymeOnly.segment("584");
  EXPECT_EQ(result.segments,
            (std::vector<Segment>{{Kind::kLiteral, "584", ""}}));
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

TEST_F(MixedInputSegmenterTest, AcceptsNonCanonicalComponentOrder) {
  MixedInputSegmenter segmenter([](const std::string&) { return true; });
  auto canonical = segmenter.segment("5j;4");
  auto reordered = segmenter.segment("5;j4");

  ASSERT_EQ(canonical.segments.size(), 1);
  ASSERT_EQ(reordered.segments.size(), 1);
  EXPECT_EQ(canonical.segments[0].kind, Kind::kChinese);
  EXPECT_EQ(reordered.segments[0].kind, Kind::kChinese);
  EXPECT_EQ(canonical.segments[0].reading, reordered.segments[0].reading);
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
