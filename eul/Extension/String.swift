//
//  String.swift
//  eul
//
//  Created by Gao Sun on 2021/1/24.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Foundation
import Localize_Swift

extension String {
    func deletingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }

    func localized(fallback: String) -> String {
        let value = localized()
        return value == self ? fallback : value
    }
}
