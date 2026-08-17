// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#ifndef SRC_ENGINE_MIXEDINPUTLANGUAGEMODEL_H_
#define SRC_ENGINE_MIXEDINPUTLANGUAGEMODEL_H_

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

#include "gramambular2/language_model.h"

namespace McBopomofo {

// Adds session-scoped literal readings without allowing them to form phrases
// with Chinese readings. The wrapped language model remains non-owning.
class MixedInputLanguageModel
    : public Formosa::Gramambular2::LanguageModel {
 public:
  explicit MixedInputLanguageModel(LanguageModel* languageModel);

  std::vector<Unigram> getUnigrams(const std::string& reading) override;
  bool hasUnigrams(const std::string& reading) override;

  [[nodiscard]] std::string registerLiteral(std::string value);
  [[nodiscard]] bool isLiteralReading(const std::string& reading) const;
  void clearLiterals();

 private:
  LanguageModel* languageModel_;
  uint64_t nextLiteralId_ = 0;
  std::unordered_map<std::string, std::string> literals_;
};

}  // namespace McBopomofo

#endif  // SRC_ENGINE_MIXEDINPUTLANGUAGEMODEL_H_
