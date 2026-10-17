import Foundation
@main struct AudioTests {
    static func main() {
        let controller = AudioController(bundle:Bundle(path:CommandLine.arguments[1])!)
        var config = Configuration(); config.focusSounds = true
        for _ in 0..<1000 { controller.reconcile(running:true,configuration:config) }
        precondition(controller.backgroundStarts == 1 && controller.activeBackgroundPlayers == 1)
        config.focusSound = "heart-beat"; controller.reconcile(running:true,configuration:config)
        precondition(controller.backgroundStarts == 2 && controller.activeBackgroundPlayers == 1)
        config.focusSounds = false; controller.reconcile(running:true,configuration:config)
        precondition(controller.activeBackgroundPlayers == 0)
        config.focusSounds = true; controller.reconcile(running:true,configuration:config)
        controller.reconcile(running:false,configuration:config)
        precondition(controller.activeBackgroundPlayers == 0)
        print("PASS 1000 reconciliations create one loop; switching replaces; disabling/stopping removes loop")
    }
}
