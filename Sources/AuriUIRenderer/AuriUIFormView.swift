#if os(iOS) || os(macOS)
//
//  AuriUIFormView.swift
//  Auri
//
//  Native SwiftUI rendering for capability-gated AuriUI forms. The package
//  owns values and validation; this file owns focus, disclosure, and review.
//

import AuriUI
import Foundation
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIFormView: View {
    let form: AuriUIForm
    let session: AuriUIScreenSession
    let onAction: (AuriUIAction) -> Void

    @State private var attemptedSubmit = false
    @State private var touchedFieldIDs: Set<String> = []
    @State private var isShowingConfirmation = false
    @FocusState private var focusedFieldID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 8) {
            VisualSectionTitle(title: form.title)

            if session.canSubmitForm(to: form.capabilityID) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(form.fields) { field in
                        AuriUIFormFieldView(
                            field: field,
                            value: $session[formID: form.id, fieldID: field.id],
                            errorMessage: errorMessage(for: field),
                            focusedFieldID: $focusedFieldID,
                            isLastTextField: isLastTextField(field.id),
                            onSubmit: { advanceFocus(after: field.id) }
                        )
                    }

                    Button(action: prepareSubmission) {
                        Text(form.submit.label)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(Color.white)
                            .background(
                                accent,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(VisualPressableButtonStyle())
                    .disabled(session.phase != .ready)
                    .accessibilityIdentifier("auriui.form.\(form.id).submit")
                    .accessibilityHint(Text("Reviews the entered details before continuing"))
                }
                .padding(14)
                .visualCard(treatment: .grouped)
                .animation(
                    reduceMotion ? nil : VisualMotion.standard(reduceMotion: false),
                    value: attemptedSubmit
                )
                .animation(
                    reduceMotion ? nil : VisualMotion.standard(reduceMotion: false),
                    value: touchedFieldIDs
                )
            } else {
                unavailableView
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(form.title))
        .confirmationDialog(
            form.confirmation ?? String(localized: "Continue with these details?"),
            isPresented: $isShowingConfirmation,
            titleVisibility: .visible
        ) {
            Button(form.submit.label, action: confirmSubmission)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            let summary = session.formReviewSummary(form.id)
            if !summary.isEmpty {
                Text(summary)
            }
        }
        .onChange(of: focusedFieldID) { oldValue, _ in
            if let oldValue {
                touchedFieldIDs.insert(oldValue)
            }
        }
    }

    private var unavailableView: some View {
        Label {
            Text("This action isn't available on this device.")
                .font(.subheadline)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .visualCard(treatment: .subtle)
        .accessibilityLabel(Text("Form unavailable. This action isn't available on this device."))
    }

    private func prepareSubmission() {
        guard session.phase == .ready else { return }
        attemptedSubmit = true
        touchedFieldIDs.formUnion(form.fields.map(\.id))

        guard session.isFormValid(form.id) else {
            VisualHaptics.selection()
            focusFirstInvalidTextField()
            return
        }

        focusedFieldID = nil
        isShowingConfirmation = true
    }

    private func confirmSubmission() {
        guard session.canSubmitForm(to: form.capabilityID),
              session.phase == .ready,
              session.isFormValid(form.id) else {
            return
        }
        VisualHaptics.tap()
        onAction(session.interpolated(form.submit.action, formID: form.id))
    }

    private func advanceFocus(after fieldID: String) {
        touchedFieldIDs.insert(fieldID)
        let textFields = form.fields.filter { $0.kind == .text || $0.kind == .textArea }
        guard let index = textFields.firstIndex(where: { $0.id == fieldID }),
              textFields.indices.contains(index + 1) else {
            focusedFieldID = nil
            return
        }
        focusedFieldID = textFields[index + 1].id
    }

    private func isLastTextField(_ fieldID: String) -> Bool {
        form.fields.last(where: { $0.kind == .text || $0.kind == .textArea })?.id == fieldID
    }

    private func focusFirstInvalidTextField() {
        guard let invalidID = session.firstInvalidFieldID(in: form.id),
              let field = form.fields.first(where: { $0.id == invalidID }),
              field.kind == .text || field.kind == .textArea else {
            focusedFieldID = nil
            return
        }
        focusedFieldID = invalidID
    }

    private func errorMessage(for field: AuriUIFormField) -> String? {
        guard attemptedSubmit || touchedFieldIDs.contains(field.id),
              let issue = session.formValidationIssue(formID: form.id, fieldID: field.id) else {
            return nil
        }

        switch issue {
        case .required:
            return String(localized: "This field is required.")
        case .tooShort(let minimum):
            return String(localized: "Enter at least \(minimum) characters.")
        case .tooLong(let maximum):
            return String(localized: "Use no more than \(maximum) characters.")
        case .invalidSelection:
            return String(localized: "Choose one of the available options.")
        case .invalidDate:
            return String(localized: "Choose a valid date.")
        case .invalidNumber:
            return String(localized: "Choose a valid value.")
        case .belowMinimum(let minimum):
            return String(localized: "Choose \(String(describing: minimum)) or more.")
        case .aboveMaximum(let maximum):
            return String(localized: "Choose \(String(describing: maximum)) or less.")
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIFormFieldView: View {
    let field: AuriUIFormField
    @Binding var value: String
    let errorMessage: String?
    @FocusState.Binding var focusedFieldID: String?
    let isLastTextField: Bool
    let onSubmit: () -> Void

    @ScaledMetric(relativeTo: .body) private var textAreaHeight = 104.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(field.label)
                    .font(.subheadline.weight(.semibold))
                if field.isRequired {
                    Text("Required")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            control
                .accessibilityIdentifier("auriui.form.field.\(field.id)")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
                    .accessibilityLabel(Text("Error: \(errorMessage)"))
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.kind {
        case .text:
            TextField(field.placeholder ?? field.label, text: $value)
                .textFieldStyle(.roundedBorder)
                .focused($focusedFieldID, equals: field.id)
                .submitLabel(isLastTextField ? .done : .next)
                .onSubmit(onSubmit)

        case .textArea:
            ZStack(alignment: .topLeading) {
                if value.isEmpty, let placeholder = field.placeholder {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $value)
                    .scrollContentBackground(.hidden)
                    .focused($focusedFieldID, equals: field.id)
            }
            .frame(minHeight: textAreaHeight)
            .padding(4)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }

        case .select:
            Picker(field.label, selection: $value) {
                ForEach(field.options) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

        case .date:
            DatePicker(field.label, selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

        case .slider:
            if let configuration = AuriUISliderConfiguration(field: field) {
                VStack(alignment: .leading, spacing: 5) {
                    Slider(
                        value: sliderBinding(configuration: configuration),
                        in: configuration.range,
                        step: configuration.step
                    )
                    .accessibilityLabel(Text(field.label))
                    .accessibilityValue(Text(sliderDisplayValue))
                    Text(sliderDisplayValue)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            } else {
                Label("This field is unavailable.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { AuriUIFormState.date(from: value) ?? Date() },
            set: { value = AuriUIFormState.string(from: $0) }
        )
    }

    private func sliderBinding(configuration: AuriUISliderConfiguration) -> Binding<Double> {
        Binding(
            get: { configuration.value(from: value) },
            set: { value = Self.wireNumber($0) }
        )
    }

    private var sliderDisplayValue: String {
        guard let unit = field.unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }

    private static func wireNumber(_ value: Double) -> String {
        var result = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}

/// The parser validates generated fields, but hosts can also construct fields
/// directly. Reject invalid control inputs before SwiftUI sees them.
@available(iOS 17.0, macOS 14.0, *)
struct AuriUISliderConfiguration {
    let range: ClosedRange<Double>
    let step: Double

    init?(field: AuriUIFormField) {
        let lower = field.minimum.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
        let upper = field.maximum.map { NSDecimalNumber(decimal: $0).doubleValue } ?? max(lower + 1, 1)
        let step = field.step.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 1
        guard lower.isFinite, upper.isFinite, lower < upper,
              step.isFinite, step > 0,
              ((upper - lower) / step).isFinite else {
            return nil
        }
        self.range = lower...upper
        self.step = step
    }

    func value(from text: String) -> Double {
        guard let value = Double(text), value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
#endif
