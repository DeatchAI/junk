//
//  Persistence.swift
//  lazzy
//
//  Created by Yakshit Chhipa on 05/12/25.
//

import CoreData
import os

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
        return result
    }()

    let container: NSPersistentContainer
    private static let logger = Logger(subsystem: "app.getlazzy", category: "persistence")

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "lazzy")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        Self.loadStore(into: container, allowRecovery: !inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func loadStore(into container: NSPersistentContainer, allowRecovery: Bool) {
        container.loadPersistentStores { description, error in
            guard error != nil else { return }
            logger.error("The local Core Data store could not be opened.")

            guard allowRecovery,
                  let storeURL = description.url,
                  preserveStoreFiles(at: storeURL)
            else {
                loadInMemoryFallback(into: container)
                return
            }

            removeStoreFiles(at: storeURL)
            container.loadPersistentStores { _, retryError in
                if retryError != nil {
                    logger.error("A clean local Core Data store could not be created; using memory for this launch.")
                    loadInMemoryFallback(into: container)
                } else {
                    logger.notice("A damaged local store was preserved and replaced with a clean store.")
                }
            }
        }
    }

    private static func loadInMemoryFallback(into container: NSPersistentContainer) {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if error != nil {
                logger.fault("The in-memory Core Data fallback could not be opened.")
            }
        }
    }

    private static func preserveStoreFiles(at storeURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return false }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let recoveryDirectory = applicationSupport
            .appendingPathComponent("Detach/Recovery/CoreData-\(timestamp)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            var copiedAnyFile = false
            for url in storeFileURLs(for: storeURL) where fileManager.fileExists(atPath: url.path) {
                try fileManager.copyItem(
                    at: url,
                    to: recoveryDirectory.appendingPathComponent(url.lastPathComponent)
                )
                copiedAnyFile = true
            }
            return copiedAnyFile
        } catch {
            logger.error("The damaged local store could not be preserved.")
            return false
        }
    }

    private static func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        for url in storeFileURLs(for: storeURL) where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]
    }
}
