import Foundation

final class UndoRedoManager {
    private var undoStack: [EditorCommand] = []
    private var redoStack: [EditorCommand] = []

    var canUndo: Bool {
        undoStack.isEmpty == false
    }

    var canRedo: Bool {
        redoStack.isEmpty == false
    }

    func record(_ command: EditorCommand) {
        undoStack.append(command)
        redoStack.removeAll()
    }

    func undo() -> EditorCommand? {
        guard let command = undoStack.popLast() else { return nil }
        redoStack.append(command)
        return command
    }

    func redo() -> EditorCommand? {
        guard let command = redoStack.popLast() else { return nil }
        undoStack.append(command)
        return command
    }
}
