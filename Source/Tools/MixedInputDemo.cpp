// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include <filesystem>
#include <iostream>
#include <string>

#include "McBopomofoLM.h"
#include "MixedInputSegmenter.h"

namespace {

std::string Render(
    const McBopomofo::MixedInputSegmenter::Result& result,
    McBopomofo::McBopomofoLM& languageModel) {
  std::string output;
  for (const auto& segment : result.segments) {
    if (segment.kind ==
        McBopomofo::MixedInputSegmenter::SegmentKind::kLiteral) {
      output += segment.raw;
      continue;
    }
    auto unigrams = languageModel.getUnigrams(segment.reading);
    output += unigrams.empty() ? segment.raw : unigrams.front().value();
  }
  return output;
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc > 2) {
    std::cerr << "Usage: MixedInputDemo [/path/to/data.txt]\n";
    return 1;
  }

  std::filesystem::path dataPath = argc == 2
                                       ? std::filesystem::path(argv[1])
                                       : std::filesystem::path(argv[0])
                                                 .parent_path() / "data.txt";

  McBopomofo::McBopomofoLM languageModel;
  languageModel.loadLanguageModel(dataPath.c_str());
  if (!languageModel.isDataModelLoaded()) {
    std::cerr << "Unable to load language model: " << dataPath << "\n";
    return 2;
  }

  McBopomofo::MixedInputSegmenter segmenter(
      [&languageModel](const std::string& reading) {
        return languageModel.hasUnigrams(reading);
      });

  std::cout << "McBopomofo mixed input demo\n"
            << "Enter Standard Bopomofo key sequences. A trailing space "
               "completes first tone; an empty line exits.\n";

  std::string raw;
  while (std::cout << "> " && std::getline(std::cin, raw) && !raw.empty()) {
    auto boundary = McBopomofo::MixedInputSegmenter::Boundary::kEnter;
    if (raw.back() == ' ') {
      raw.pop_back();
      boundary = McBopomofo::MixedInputSegmenter::Boundary::kSpace;
    }
    auto result = segmenter.segment(raw, boundary);
    std::string chinese = Render(result, languageModel);
    std::cout << "Automatic: " << chinese << '\n';
    if (chinese != raw) {
      std::cout << "Chinese interpretation: " << chinese << '\n'
                << "English interpretation: " << raw << '\n';
    }
  }
  return 0;
}
