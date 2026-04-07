import Foundation
import Logging

extension Logger {
    @TaskLocal
    static var currentScope: Logger?
}
