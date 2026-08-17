// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include "MixedInputSegmenter.h"

#include <string>
#include <utility>

#include "Mandarin/Mandarin.h"

namespace McBopomofo {
namespace {

bool IsToneKey(char key) {
  return key == '3' || key == '4' || key == '6' || key == '7';
}

size_t PhoneticKeyCount(std::string_view keys) {
  return keys.empty() ? 0 : keys.size() - (IsToneKey(keys.back()) ? 1 : 0);
}

}  // namespace

MixedInputSegmenter::MixedInputSegmenter(HasUnigrams hasUnigrams)
    : hasUnigrams_(std::move(hasUnigrams)) {}

MixedInputSegmenter::Result MixedInputSegmenter::segment(
    std::string_view raw, Boundary boundary) const {
  Result result;
  if (raw.empty()) {
    return result;
  }

  if (HasStructuralAsciiEvidence(raw)) {
    result.protectedAscii = true;
    appendLiteral(result.segments, raw);
    return result;
  }

  size_t pendingStart = 0;
  for (size_t toneIndex = 0; toneIndex < raw.size(); ++toneIndex) {
    if (!IsToneKey(raw[toneIndex])) {
      continue;
    }

    std::optional<size_t> chineseStart;
    std::optional<std::string> reading;
    for (size_t start = pendingStart; start < toneIndex; ++start) {
      std::string_view keys = raw.substr(start, toneIndex - start + 1);
      std::optional<std::string> candidate = strictReading(keys, false);
      if (!candidate || !hasUnigrams_(*candidate)) {
        continue;
      }

      // When a Chinese suffix follows an ASCII prefix, require at least two
      // phonetic keys. This keeps tokens such as "version4" intact while
      // still allowing an entire short token such as "a3" to be Chinese.
      if (start > pendingStart && PhoneticKeyCount(keys) < 2) {
        continue;
      }

      chineseStart = start;
      reading = std::move(candidate);
      break;
    }

    if (!chineseStart || !reading) {
      continue;
    }

    appendLiteral(result.segments,
                  raw.substr(pendingStart, *chineseStart - pendingStart));
    result.segments.push_back({SegmentKind::kChinese,
                               std::string(raw.substr(
                                   *chineseStart, toneIndex - *chineseStart + 1)),
                               *reading});
    pendingStart = toneIndex + 1;
  }

  std::string_view tail = raw.substr(pendingStart);
  if (boundary == Boundary::kSpace && !tail.empty()) {
    std::optional<std::string> reading = strictReading(tail, true);
    if (reading && hasUnigrams_(*reading)) {
      result.segments.push_back(
          {SegmentKind::kChinese, std::string(tail), *reading});
      return result;
    }
  }

  appendLiteral(result.segments, tail);
  return result;
}

bool MixedInputSegmenter::IsSupportedAscii(char key) {
  unsigned char value = static_cast<unsigned char>(key);
  return value >= 0x20 && value <= 0x7e;
}

bool MixedInputSegmenter::HasStructuralAsciiEvidence(std::string_view raw) {
  size_t consecutiveDigits = 0;
  for (char key : raw) {
    unsigned char value = static_cast<unsigned char>(key);
    if (value >= 'A' && value <= 'Z') {
      return true;
    }

    switch (key) {
      case '@':
      case '.':
      case '/':
      case '\\':
      case '_':
      case '+':
      case '#':
      case '=':
      case ':':
        return true;
      default:
        break;
    }

    if (value >= '0' && value <= '9') {
      ++consecutiveDigits;
    } else {
      consecutiveDigits = 0;
    }
    if (consecutiveDigits >= 3) {
      return true;
    }
  }
  return false;
}

std::optional<std::string> MixedInputSegmenter::strictReading(
    std::string_view keys, bool completesFirstTone) const {
  if (keys.empty()) {
    return std::nullopt;
  }

  if (!completesFirstTone && !IsToneKey(keys.back())) {
    return std::nullopt;
  }
  if (completesFirstTone && IsToneKey(keys.back())) {
    return std::nullopt;
  }

  const auto* layout =
      Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout();
  std::string sequence(keys);
  for (char key : sequence) {
    if (layout->keyToComponents(key).empty()) {
      return std::nullopt;
    }
  }

  Formosa::Mandarin::BopomofoSyllable syllable =
      layout->syllableFromKeySequence(sequence);
  if (syllable.isEmpty() ||
      (!completesFirstTone && !syllable.hasToneMarker())) {
    return std::nullopt;
  }

  // The normal reading buffer permits later keys to overwrite a component.
  // A strict candidate must instead round-trip to the exact canonical order.
  if (layout->keySequenceFromSyllable(syllable) != sequence) {
    return std::nullopt;
  }

  return syllable.composedString();
}

void MixedInputSegmenter::appendLiteral(std::vector<Segment>& segments,
                                        std::string_view raw) {
  if (raw.empty()) {
    return;
  }
  if (!segments.empty() && segments.back().kind == SegmentKind::kLiteral) {
    segments.back().raw.append(raw);
    return;
  }
  segments.push_back({SegmentKind::kLiteral, std::string(raw), {}});
}

}  // namespace McBopomofo
