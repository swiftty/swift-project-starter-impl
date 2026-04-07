import Foundation
import System

// default config
extension Config {
    static func forApplicationDefault(name: String, packagePath: FilePath) -> Self {
        Self.init(
            project: .application(
                name: name,
                projectRoot: "..",
                makefile: .default(
                    projectName: name,
                    projectRoot: "..",
                    packageDirectory: packagePath.directory().lastComponent!,
                ),
                xcoddgen: .default(
                    projectName: name,
                    packageDirectory: packagePath.directory().lastComponent!,
                ),
                resources: [
                    .`WorkspaceSettings.xcsettings`(name: name),
                    .`.gitignore`(path: "Sources"),
                    .`.gitignore`(path: "Resources"),
                    .`.swift-format`
                ]
            ),
            dependencies: [
                .init(url: "https://github.com/swiftty/XcodeGenBinary", from: "2.45.3"),
                .init(url: "https://github.com/swiftty/swift-format-plugin", from: "1.0.0"),
            ],
            swiftSettings: [
                .defaultIsolation(.MainActor),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    }

    static let forLibraryDefault = Self.init(
        project: .library(
            resources: [
                .`.swift-format`
            ]
        ),
        dependencies: [
            .init(url: "https://github.com/swiftty/swift-format-plugin", from: "1.0.0"),
        ],
        swiftSettings: [
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ]
    )
}

extension Config.Makefile {
    static func `default`(
        projectName: String,
        projectRoot: FilePath,
        packageDirectory: FilePath.Component,
    ) -> Self {
        Self.init(
            content: """
            PROJECT_NAME := \(projectName)
            PACKAGE_DIR := \(packageDirectory.string)
            XCODE_PROJECT := $(PROJECT_NAME).xcodeproj
            XCUSERDATA_DIR := $(XCODE_PROJECT)/project.xcworkspace/xcuserdata/$(shell whoami).xcuserdatad
            XCSHAREDDATA_DIR := $(XCODE_PROJECT)/project.xcworkspace/xcshareddata

            SWIFT = swift$(1) --package-path $(PACKAGE_DIR) --build-path DerivedData/$(PROJECT_NAME)/SourcePackages
            
            .PHONY: project
            project:
            \t@$(call SWIFT, package) plugin --allow-writing-to-directory . xcodegen

            \t@mkdir -p $(XCUSERDATA_DIR)
            \t@cp -f $(XCSHAREDDATA_DIR)/WorkspaceSettings.xcsettings $(XCUSERDATA_DIR)/WorkspaceSettings.xcsettings
            
            .PHONY: format
            format:
            \t@$(call SWIFT, package) plugin --allow-writing-to-package-directory --allow-writing-to-directory \(projectRoot.string) format-source-code

            .PHONY: test
            test:
            \t$(call SWIFT, test)

            .PHONY: resolve
            resolve:
            \t$(call SWIFT, package) resolve
            """
        )
    }
}

extension Config.XcodeGen {
    static func `default`(
        projectName: String,
        packageDirectory: FilePath.Component,
    ) -> Self {
        Self.init(content: """
        name: \(projectName)

        # base settings
        # configs
        configs:
          Debug: debug
          Release: release

        # settings
        settings:
          base:
            VERSIONING_SYSTEM: apple-generic
          configs:
            Debug:
              OTHER_SWIFT_FLAGS: -DDEBUG

        options:
          bundleIdPrefix: <$ bundle id prefix $>
          developmentLanguage: ja
          localPackagesGroup: ""

        packages:
          \(packageDirectory.string):
            path: \(packageDirectory.string)

        targets:
          HostApp:
            type: application
            platform: <$ platform $>
            settings:
              base:
                GENERATE_INFOPLIST_FILE: YES
                ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
                SWIFT_VERSION: "6"
              configs:
                Debug:
                  INFOPLIST_PREPROCESS: YES
            sources:
              - Sources
              - Resources
              - path: project.yml
                group: Configurations
                buildPhase: none
            dependencies:
              - package: \(packageDirectory.string)
                product: <$ package product $>

        """)
    }
}

extension Config.Project.File {
    static let `.swift-format` = Self.init(
        filePath: ".swift-format",
        content: """
        {
          "indentation": {
            "spaces": 4
          },
          "lineLength": 120,
          "rules": {
            "NoAccessLevelOnExtensionDeclaration": false
          },
          "version": 1
        }
        """
    )

    static func `WorkspaceSettings.xcsettings`(name: String) -> Self {
        Self.init(
            filePath: "\(name).xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings",
            content: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>BuildLocationStyle</key>
            \t<string>UseAppPreferences</string>
            \t<key>CustomBuildLocationType</key>
            \t<string>RelativeToDerivedData</string>
            \t<key>DerivedDataCustomLocation</key>
            \t<string>DerivedData</string>
            \t<key>DerivedDataLocationStyle</key>
            \t<string>WorkspaceRelativePath</string>
            </dict>
            </plist>  
            """
        )
    }

    static func `.gitignore`(path: String) -> Self {
        Self.init(filePath: FilePath(path).appending(".gitignore").string, content: "")
    }
}

/**
 *
 * ```json
 * {
 *   "project": {
 *     "type": "application" | "library",
 *     // available if type == "application"
 *     "name": "xxx",
 *     "projectRoot": "..",
 *     "Makefile": {
 *       "content": "xxx"
 *     },
 *     "XcodeGen": {
 *       "content": "xxx"
 *     }
 *   },
 *   "dependencies": [
 *     { "url": "...", "from": "x.y.z" }
 *   ],
 *   "swiftSettings": [
 *     { "defaultIsolation": "MainActor" },
 *     { "enableUpcomingFeature": "InternalImportsByDefault" },
 *     { "enableExperimentalFeature": "xxx" }
 *   ]
 * }
 * ```
 *
 */
