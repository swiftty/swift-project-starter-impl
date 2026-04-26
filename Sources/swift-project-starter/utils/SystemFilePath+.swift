#if canImport(System)
    import System
    import Foundation

    func url(from path: String) -> URL? {
        URL(filePath: System::FilePath(path))
    }
#endif
