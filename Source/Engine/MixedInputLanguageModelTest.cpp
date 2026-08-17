// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include "MixedInputLanguageModel.h"

#include <string>
#include <vector>

#include "gtest/gtest.h"

namespace McBopomofo {
namespace {

class TestLanguageModel : public Formosa::Gramambular2::LanguageModel {
 public:
  std::vector<Unigram> getUnigrams(const std::string& reading) override {
    return reading == "reading" ? std::vector<Unigram>{Unigram("字", -1)}
                                : std::vector<Unigram>{};
  }

  bool hasUnigrams(const std::string& reading) override {
    return reading == "reading";
  }
};

TEST(MixedInputLanguageModelTest, DelegatesChineseReadings) {
  TestLanguageModel base;
  MixedInputLanguageModel model(&base);

  EXPECT_TRUE(model.hasUnigrams("reading"));
  ASSERT_EQ(model.getUnigrams("reading").size(), 1);
  EXPECT_EQ(model.getUnigrams("reading")[0].value(), "字");
}

TEST(MixedInputLanguageModelTest, RegistersOpaqueLiteralReadings) {
  TestLanguageModel base;
  MixedInputLanguageModel model(&base);

  std::string key = model.registerLiteral("@");
  EXPECT_EQ(key.find("@"), std::string::npos);
  EXPECT_TRUE(model.isLiteralReading(key));
  EXPECT_TRUE(model.hasUnigrams(key));
  ASSERT_EQ(model.getUnigrams(key).size(), 1);
  EXPECT_EQ(model.getUnigrams(key)[0].value(), "@");
  EXPECT_FALSE(model.hasUnigrams(key + "-reading"));

  model.clearLiterals();
  EXPECT_FALSE(model.hasUnigrams(key));
}

}  // namespace
}  // namespace McBopomofo
