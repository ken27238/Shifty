import CoreData
#if !WIDGET
import WidgetKit
#endif

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Shifty")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Use FileManager to get the app group container URL
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourcompany.Shifty") {
                let storeURL = url.appendingPathComponent("Shifty.sqlite")
                let storeDescription = NSPersistentStoreDescription(url: storeURL)
                container.persistentStoreDescriptions = [storeDescription]
            }
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                
                // Reload widget timelines after saving changes
                #if !WIDGET
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
