// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include "MixedInputLanguageModel.h"

#include <string>
#include <utility>
#include <vector>

namespace McBopomofo {

MixedInputLanguageModel::MixedInputLanguageModel(LanguageModel* languageModel)
    : languageModel_(languageModel) {}

std::vector<MixedInputLanguageModel::Unigram>
MixedInputLanguageModel::getUnigrams(const std::string& reading) {
  auto literal = literals_.find(reading);
  if (literal != literals_.end()) {
    return {Unigram(literal->second, 0)};
  }
  return languageModel_->getUnigrams(reading);
}

bool MixedInputLanguageModel::hasUnigrams(const std::string& reading) {
  return literals_.contains(reading) || languageModel_->hasUnigrams(reading);
}

std::string MixedInputLanguageModel::registerLiteral(std::string value) {
  std::string reading = "_mixed_literal_" + std::to_string(nextLiteralId_++);
  literals_.insert_or_assign(reading, std::move(value));
  return reading;
}

bool MixedInputLanguageModel::isLiteralReading(
    const std::string& reading) const {
  return literals_.contains(reading);
}

void MixedInputLanguageModel::clearLiterals() {
  literals_.clear();
  nextLiteralId_ = 0;
}

}  // namespace McBopomofo
