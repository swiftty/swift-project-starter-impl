import Foundation
import SystemPackage

extension FilePath {
    func directory() -> FilePath {
        removingLastComponent()
    }

    func standardized() -> FilePath {
        guard let url = URL(filePath: self)?.standardizedFileURL else {
            return self
        }
        return FilePath(url.path(percentEncoded: false))
    }

    func relative(from base: FilePath) -> FilePath {
        let base = Array(base.standardized().components)
        let dest = Array(self.standardized().components)

        var i = 0
        while i < min(base.count, dest.count), base[i] == dest[i] {
            i += 1
        }

        let up = Array(repeating: FilePath.Component(".."), count: base.count - i)
        let down = Array(dest[i...])

        return FilePath(root: root, up + down)
    }
}

extension URL {
    init?(filePath: SystemPackage::FilePath) {
        #if canImport(System)
            self.init(filePath: SystemFilePath(filePath.string))
        #else
            self.init(fileURLWithPath: filePath.string)
        #endif
    }
}
