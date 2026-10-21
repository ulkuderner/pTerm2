import SwiftUI

@main
enum PtermMain {
    static func main() {
        if CommandLine.arguments.contains("--pterm-zsh") {
            exit(pterm_enter_zsh())
        }
        iTerm2PadApp.main()
    }
}

@_silgen_name("pterm_enter_zsh")
func pterm_enter_zsh() -> Int32
