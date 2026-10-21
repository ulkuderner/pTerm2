import SwiftUI

@main
enum PtermMain {
    static func main() {
        #if !targetEnvironment(simulator)
        if CommandLine.arguments.contains("--pterm-zsh") {
            pterm_activate_tty()
            exit(pterm_enter_zsh())
        }
        #endif
        iTerm2PadApp.main()
    }
}

#if !targetEnvironment(simulator)
@_silgen_name("pterm_activate_tty")
func pterm_activate_tty()

@_silgen_name("pterm_enter_zsh")
func pterm_enter_zsh() -> Int32
#endif
