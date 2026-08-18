// Copyright (c) 2026 and onwards The McBopomofo Authors.
// See the LICENSE file in the project root for license information.

import Foundation

/// Local-build fallback used when SwiftyOpenCC is not available. The mixed
/// input feature does not depend on Chinese script conversion.
public final class OpenCCBridge: NSObject {
    @objc(sharedInstance) public static let shared = OpenCCBridge()

    private override init() {
        super.init()
    }

    @objc public func convertToSimplified(_ string: String) -> String? {
        string
    }

    @objc public func convertToTraditional(_ string: String) -> String? {
        string
    }
}
