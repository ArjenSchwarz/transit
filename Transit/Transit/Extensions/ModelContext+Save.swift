import SwiftData

// Save-with-recovery helpers. There are two strategies and they are NOT
// interchangeable:
//
// * `saveOrRollback` — for UPDATES and DELETES of already-persisted models. On
//   failure the context is rolled back through `safeRollback()`, reverting the
//   mutation in memory as well as in the store.
//
// * `insertOrDelete` — for CREATES. On failure the freshly inserted model is
//   deleted from the context. Rollback is wrong here: it does not reliably
//   re-fault a newly inserted `@Model` (T-452), so the object would stay
//   registered in the shared context and get committed by the next unrelated
//   `save()` (T-486).
//
// A third strategy exists in the codebase and deliberately uses neither helper:
// background display-ID promotion resets only the field it just assigned,
// because a context-wide rollback would discard the user's unrelated unsaved
// edits on the shared main context (T-449).

extension ModelContext {

    /// Applies `mutation`, then saves. If either step throws, the context is
    /// rolled back via `safeRollback()` and the error is rethrown.
    ///
    /// Pass `save: false` to apply the mutation without persisting it — the
    /// caller then owns the save. A failing mutation still rolls back.
    ///
    /// - Important: All services share `container.mainContext`, so the rollback
    ///   discards every unsaved change on that context, not only this call's.
    ///   Creation paths must use ``insertOrDelete(_:save:)`` instead.
    func saveOrRollback(save shouldSave: Bool = true, _ mutation: () throws -> Void = {}) throws {
        do {
            try mutation()
            guard shouldSave else { return }
            try save()
        } catch {
            safeRollback()
            throw error
        }
    }

    /// Inserts `model` and saves it. If the save throws, the inserted model is
    /// deleted from the context and the error is rethrown, so a later unrelated
    /// save cannot resurrect it.
    ///
    /// `save` is injectable so tests can simulate a failing save.
    ///
    /// - Important: Creation must not use ``saveOrRollback(save:_:)`` — see the
    ///   note at the top of this file (T-452, T-486).
    func insertOrDelete<Model: PersistentModel>(
        _ model: Model,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        insert(model)
        do {
            try save(self)
        } catch {
            delete(model)
            throw error
        }
    }
}

extension ModelContext {

    /// Applies `mutation`, then persists through an injected save closure. This
    /// is the injectable counterpart to `saveOrRollback(save:_:)`: updates and
    /// deletes still recover with `safeRollback()` if either the mutation or the
    /// supplied save fails.
    func saveOrRollback(
        save: (ModelContext) throws -> Void,
        _ mutation: () throws -> Void = {}
    ) throws {
        do {
            try mutation()
            try save(self)
        } catch {
            safeRollback()
            throw error
        }
    }
}
