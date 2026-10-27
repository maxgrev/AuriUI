//
//  AuriUISelectionState.swift
//  AuriUI
//
//  Deterministic client-side money and selection state for a screen. The
//  model itemizes prices; this type is the only thing that ever sums them —
//  the Burger Test's exact-arithmetic guarantee lives here.
//

import Foundation

public struct AuriUISelectionState: Equatable, Sendable {

    private struct PickGroup: Equatable, Sendable {
        var name: String
        var options: [AuriUIOption]
    }

    private var money: AuriUIMoneyContext
    private var pickGroups: [PickGroup] = []
    private var multiOptions: [AuriUIOption] = []
    private var receiptSum: Decimal = 0
    private var hasReceiptLines = false

    /// group name → selected `val`.
    private var picks: [String: String] = [:]
    /// toggled-on `val`s across multi lists.
    private var toggles: Set<String> = []

    /// Builds initial state from a parsed screen: first option of each pick
    /// group is selected unless one carries `sel`; `sel` toggles start on.
    public init(document: AuriUIDocument) {
        money = document.money
        collect(from: document.sections)

        for group in pickGroups {
            let initial = group.options.first(where: \.selectedByDefault) ?? group.options.first
            if let initial {
                picks[group.name] = initial.selectionValue
            }
        }
        for option in multiOptions where option.selectedByDefault {
            toggles.insert(option.selectionValue)
        }
    }

    private mutating func collect(from sections: [AuriUISection]) {
        for section in sections {
            switch section {
            case .list(let list):
                switch list.mode {
                case .pick(let group):
                    if let index = pickGroups.firstIndex(where: { $0.name == group }) {
                        pickGroups[index].options.append(contentsOf: list.items)
                    } else {
                        pickGroups.append(PickGroup(name: group, options: list.items))
                    }
                case .multi:
                    multiOptions.append(contentsOf: list.items)
                }
            case .receipt(_, let lines):
                hasReceiptLines = hasReceiptLines || !lines.isEmpty
                receiptSum += lines.reduce(Decimal(0)) { $0 + $1.price }
            case .tabs(let tabs):
                for tab in tabs {
                    collect(from: tab.sections)
                }
            default:
                break
            }
        }
    }

    // MARK: - Mutations

    /// Selects an option in a pick group. Unknown group/value is a no-op.
    public mutating func select(group: String, value: String) {
        guard let groupOptions = pickGroups.first(where: { $0.name == group })?.options,
              groupOptions.contains(where: { $0.selectionValue == value }) else { return }
        picks[group] = value
    }

    /// Toggles a multi-list option. Unknown value is a no-op.
    public mutating func toggle(value: String) {
        guard multiOptions.contains(where: { $0.selectionValue == value }) else { return }
        if !toggles.insert(value).inserted {
            toggles.remove(value)
        }
    }

    public func isSelected(group: String, value: String) -> Bool {
        picks[group] == value
    }

    public func isToggled(value: String) -> Bool {
        toggles.contains(value)
    }

    // MARK: - Derived values

    /// Selected pick prices + toggled add-on prices, on top of either the
    /// receipt sum (when receipt lines exist — receipts itemize everything,
    /// so a stray `state base` can never double-count) or `state base`.
    /// Exact `Decimal` math.
    public var total: Decimal {
        var sum = hasReceiptLines ? receiptSum : money.base
        for group in pickGroups {
            if let value = picks[group.name],
               let option = group.options.first(where: { $0.selectionValue == value }) {
                sum += option.price
            }
        }
        for option in multiOptions where toggles.contains(option.selectionValue) {
            sum += option.price
        }
        return sum
    }

    /// Currency-formatted total, e.g. `$17.49`. Locale defaults to en_US so
    /// tests and prompts are deterministic; pass the user's locale in UI.
    public func formattedTotal(locale: Locale = Locale(identifier: "en_US")) -> String {
        Self.format(total, currencyCode: money.currencyCode, locale: locale)
    }

    /// Plain currency formatting in the screen's currency (receipt lines).
    public func formattedPrice(_ amount: Decimal, locale: Locale = Locale(identifier: "en_US")) -> String {
        Self.format(amount, currencyCode: money.currencyCode, locale: locale)
    }

    /// Formats a single option price as its display tag: `Included` for
    /// zero, `+$2.00` / `−$1.00` otherwise.
    public func priceTag(for price: Decimal, locale: Locale = Locale(identifier: "en_US")) -> String {
        if price == 0 {
            return "Included"
        }
        let magnitude = Self.format(abs(price), currencyCode: money.currencyCode, locale: locale)
        return price > 0 ? "+\(magnitude)" : "−\(magnitude)"
    }

    /// Comma-joined titles of the current selection — pick groups first (in
    /// document order), then toggled add-ons. Feeds `{selections}`.
    public var selectionSummary: String {
        var titles: [String] = []
        for group in pickGroups {
            if let value = picks[group.name],
               let option = group.options.first(where: { $0.selectionValue == value }) {
                titles.append(option.title)
            }
        }
        for option in multiOptions where toggles.contains(option.selectionValue) {
            titles.append(option.title)
        }
        return titles.joined(separator: ", ")
    }

    // MARK: - Interpolation

    /// Replaces `{total}` and `{selections}` in a display string or action
    /// argument. Actions must be interpolated before dispatch so the next
    /// screen's composer receives exact numbers to copy.
    public func interpolate(_ string: String, locale: Locale = Locale(identifier: "en_US")) -> String {
        guard string.contains("{") else { return string }
        return string
            .replacingOccurrences(of: "{total}", with: formattedTotal(locale: locale))
            .replacingOccurrences(of: "{selections}", with: selectionSummary)
    }

    public func interpolated(_ action: AuriUIAction, locale: Locale = Locale(identifier: "en_US")) -> AuriUIAction {
        switch action {
        case .send(let prompt):
            return .send(prompt: interpolate(prompt, locale: locale))
        case .nav(let brief):
            return .nav(brief: interpolate(brief, locale: locale))
        case .url, .hostCapability:
            return action
        }
    }

    private static func format(_ amount: Decimal, currencyCode: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
