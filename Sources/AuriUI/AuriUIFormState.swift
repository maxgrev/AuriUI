//
//  AuriUIFormState.swift
//  AuriUI
//
//  Deterministic values, validation, review text, and action interpolation
//  for capability-gated forms. The renderer owns presentation only.
//

import Foundation

public enum AuriUIFormValidationIssue: Equatable, Sendable {
    case required
    case tooShort(minimum: Int)
    case tooLong(maximum: Int)
    case invalidSelection
    case invalidDate
    case invalidNumber
    case belowMinimum(Decimal)
    case aboveMaximum(Decimal)
}

public struct AuriUIFormState: Equatable, Sendable {
    public let form: AuriUIForm
    public private(set) var values: [String: String]

    public init(form: AuriUIForm) {
        self.form = form
        self.values = Dictionary(uniqueKeysWithValues: form.fields.map { field in
            (field.id, Self.initialValue(for: field))
        })
    }

    public subscript(fieldID: String) -> String {
        get { values[fieldID] ?? "" }
        set {
            guard form.fields.contains(where: { $0.id == fieldID }) else { return }
            values[fieldID] = newValue
        }
    }

    public func validationIssue(for fieldID: String) -> AuriUIFormValidationIssue? {
        guard let field = form.fields.first(where: { $0.id == fieldID }) else {
            return nil
        }
        return validationIssue(for: field)
    }

    public var validationIssues: [String: AuriUIFormValidationIssue] {
        Dictionary(uniqueKeysWithValues: form.fields.compactMap { field in
            validationIssue(for: field).map { (field.id, $0) }
        })
    }

    public var isValid: Bool {
        form.fields.allSatisfy { validationIssue(for: $0) == nil }
    }

    public var firstInvalidFieldID: String? {
        form.fields.first { validationIssue(for: $0) != nil }?.id
    }

    /// Concise, user-readable values for the confirmation dialog.
    public var reviewSummary: String {
        form.fields.compactMap { field in
            let value = displayValue(for: field)
            guard !value.isEmpty else { return nil }
            return "\(field.label): \(value)"
        }
        .joined(separator: "\n")
    }

    /// Replaces only placeholders declared by this form. Unknown braces stay
    /// intact, and user-entered braces cannot trigger a second interpolation.
    public func interpolate(_ string: String) -> String {
        guard string.contains("{") else { return string }
        let replacements = Dictionary(uniqueKeysWithValues: form.fields.map { field in
            (field.id, displayValue(for: field))
        })
        var result = ""
        var cursor = string.startIndex

        while let opening = string[cursor...].firstIndex(of: "{"),
              let closing = string[opening...].firstIndex(of: "}") {
            result.append(contentsOf: string[cursor..<opening])
            let keyStart = string.index(after: opening)
            let key = String(string[keyStart..<closing])
            if let replacement = replacements[key] {
                result.append(replacement)
            } else {
                result.append(contentsOf: string[opening...closing])
            }
            cursor = string.index(after: closing)
        }
        result.append(contentsOf: string[cursor...])
        return result
    }

    public func interpolated(_ action: AuriUIAction) -> AuriUIAction {
        switch action {
        case .send(let prompt):
            return .send(prompt: interpolate(prompt))
        case .nav(let brief):
            return .nav(brief: interpolate(brief))
        case .url, .hostCapability:
            return action
        }
    }

    public static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else {
            return nil
        }
        return date
    }

    public static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func validationIssue(for field: AuriUIFormField) -> AuriUIFormValidationIssue? {
        let value = values[field.id] ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return field.isRequired ? .required : nil
        }

        switch field.kind {
        case .text, .textArea:
            if let minimum = field.minimumLength, trimmed.count < minimum {
                return .tooShort(minimum: minimum)
            }
            if let maximum = field.maximumLength, value.count > maximum {
                return .tooLong(maximum: maximum)
            }
        case .select:
            guard field.options.contains(where: { $0.id == value }) else {
                return .invalidSelection
            }
        case .date:
            guard Self.date(from: value) != nil else {
                return .invalidDate
            }
        case .slider:
            guard let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
                return .invalidNumber
            }
            if let minimum = field.minimum, number < minimum {
                return .belowMinimum(minimum)
            }
            if let maximum = field.maximum, number > maximum {
                return .aboveMaximum(maximum)
            }
        }

        return nil
    }

    private func displayValue(for field: AuriUIFormField) -> String {
        let value = values[field.id] ?? ""
        switch field.kind {
        case .select:
            return field.options.first(where: { $0.id == value })?.label ?? value
        case .slider:
            guard let unit = field.unit, !unit.isEmpty, !value.isEmpty else { return value }
            return "\(value) \(unit)"
        default:
            return value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
    }

    private static func initialValue(for field: AuriUIFormField) -> String {
        if !field.initialValue.isEmpty {
            return field.initialValue
        }
        switch field.kind {
        case .select:
            return field.options.first?.id ?? ""
        case .slider:
            return field.minimum.map { String(describing: $0) } ?? ""
        default:
            return ""
        }
    }
}

public extension AuriUIDocument {
    /// Forms in render order, including tabs and detail pages. Form ids are
    /// document-wide identities and must be unique.
    var forms: [AuriUIForm] {
        func collect(from sections: [AuriUISection]) -> [AuriUIForm] {
            sections.flatMap { section in
                switch section {
                case .form(let form):
                    return [form]
                case .tabs(let tabs):
                    return tabs.flatMap { collect(from: $0.sections) }
                default:
                    return []
                }
            }
        }

        return collect(from: sections) + pages.flatMap { collect(from: $0.sections) }
    }
}
