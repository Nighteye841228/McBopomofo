// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

#include "MixedInputSegmenter.h"

#include <algorithm>
#include <string>
#include <utility>

#include "Mandarin/Mandarin.h"

namespace McBopomofo {
namespace {

bool IsToneKey(char key) {
  return key == '3' || key == '4' || key == '6' || key == '7';
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

  bool completesFirstTone = boundary == Boundary::kSpace;
  std::optional<std::string> exactReading =
      strictReading(raw, completesFirstTone);
  if (exactReading && hasUnigrams_(*exactReading)) {
    result.segments.push_back(
        {SegmentKind::kChinese, std::string(raw), *exactReading});
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

    auto readingAt = [&](size_t start) -> std::optional<std::string> {
      std::string_view keys = raw.substr(start, toneIndex - start + 1);
      std::optional<std::string> candidate = strictReading(keys, false);
      if (!candidate || !hasUnigrams_(*candidate)) {
        return std::nullopt;
      }

      return candidate;
    };

    std::optional<size_t> chineseStart;
    std::string_view wholeKeys =
        raw.substr(pendingStart, toneIndex - pendingStart + 1);
    std::optional<std::string> wholeReading = strictReading(wholeKeys, false);
    std::optional<std::string> reading;
    if (wholeReading && hasUnigrams_(*wholeReading)) {
      reading = wholeReading;
    }
    if (reading) {
      chineseStart = pendingStart;
    } else if (wholeReading) {
      // The complete key sequence is a structurally valid syllable, but it is
      // not in the language model. Keep the entire sequence literal instead
      // of dropping its onset and interpreting only a shared rhyme.
      appendLiteral(result.segments, wholeKeys);
      pendingStart = toneIndex + 1;
      continue;
    } else {
      // Prefer the shortest suffix with at least two phonetic components, then
      // fall back to a one-component syllable such as m3 (ㄩˇ). This keeps the
      // final letter in "call" out of "su3" without losing valid short forms.
      if (toneIndex >= pendingStart + 2) {
        for (size_t start = toneIndex - 1; start > pendingStart; --start) {
          size_t candidateStart = start - 1;
          reading = readingAt(candidateStart);
          if (reading) {
            chineseStart = candidateStart;
            break;
          }
        }
      }
      if (!reading && toneIndex > pendingStart) {
        size_t candidateStart = toneIndex - 1;
        reading = readingAt(candidateStart);
        if (reading) {
          chineseStart = candidateStart;
        }
      }
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
    auto firstToneReadingAt = [&](size_t start) -> std::optional<std::string> {
      std::string_view keys = raw.substr(start);
      std::optional<std::string> candidate = strictReading(keys, true);
      if (!candidate || !hasUnigrams_(*candidate)) {
        return std::nullopt;
      }
      return candidate;
    };

    std::optional<size_t> chineseStart;
    std::optional<std::string> wholeReading = strictReading(tail, true);
    std::optional<std::string> reading;
    if (wholeReading && hasUnigrams_(*wholeReading)) {
      reading = wholeReading;
    }
    if (reading) {
      chineseStart = pendingStart;
    } else if (wholeReading) {
      // As with explicit tones, never reinterpret a valid complete syllable
      // as a literal onset followed by a shorter first-tone rhyme.
      appendLiteral(result.segments, tail);
      return result;
    } else {
      for (size_t start = raw.size() - 1; start > pendingStart; --start) {
        size_t candidateStart = start - 1;
        reading = firstToneReadingAt(candidateStart);
        if (reading) {
          chineseStart = candidateStart;
          break;
        }
      }
      if (!reading && raw.size() > pendingStart) {
        size_t candidateStart = raw.size() - 1;
        reading = firstToneReadingAt(candidateStart);
        if (reading) {
          chineseStart = candidateStart;
        }
      }
    }
    if (chineseStart && reading) {
      appendLiteral(result.segments,
                    raw.substr(pendingStart, *chineseStart - pendingStart));
      result.segments.push_back({SegmentKind::kChinese,
                                 std::string(raw.substr(*chineseStart)),
                                 *reading});
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
  for (size_t index = 0; index < raw.size(); ++index) {
    char key = raw[index];
    unsigned char value = static_cast<unsigned char>(key);
    if (value >= 'A' && value <= 'Z') {
      return true;
    }

    switch (key) {
      case '@':
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

    // Period is the Standard Bopomofo key for ㄡ. An email address is already
    // protected by '@', and a URL by its scheme separator, so a period alone
    // cannot be treated as decisive ASCII evidence.
    // Slash is also the Standard Bopomofo key for ㄥ; only treat it as
    // structural ASCII when it participates in a URL scheme separator.
    if (key == ':' && index + 2 < raw.size() && raw[index + 1] == '/' &&
        raw[index + 2] == '/') {
      return true;
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

  // McBopomofo intentionally accepts component keys in a non-canonical order
  // (for example, both 5j;4 and 5;j4 form ㄓㄨㄤˋ). Keep the parser strict by
  // requiring the exact same component-key multiset after normalization. This
  // accepts reordering while rejecting overwritten or duplicate components.
  std::string normalized = layout->keySequenceFromSyllable(syllable);
  std::sort(sequence.begin(), sequence.end());
  std::sort(normalized.begin(), normalized.end());
  if (normalized != sequence) {
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
