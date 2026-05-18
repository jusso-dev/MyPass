import UIKit
import PDFKit

struct PDFExportService {

    static func generatePDF(from cardData: CardData) -> Data {
        let pageWidth: CGFloat = 612  // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { context in
            var y: CGFloat = 0

            func beginPageIfNeeded(requiredSpace: CGFloat = 60) {
                if y == 0 || y + requiredSpace > pageHeight - margin {
                    context.beginPage()
                    y = margin
                }
            }

            // --- Colours ---
            let brandBlue = UIColor(red: 0.25, green: 0.61, blue: 0.76, alpha: 1)
            let deepBlue = UIColor(red: 0.16, green: 0.42, blue: 0.56, alpha: 1)
            let sectionBg = UIColor(red: 0.95, green: 0.97, blue: 0.99, alpha: 1)

            // --- Fonts ---
            let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let sectionTitleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
            let valueFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let footerFont = UIFont.systemFont(ofSize: 8, weight: .regular)

            // --- Helper: draw section ---
            func drawSection(title: String, fields: [(String, String)]) {
                let nonEmpty = fields.filter { !$0.1.isEmpty }
                guard !nonEmpty.isEmpty else { return }

                // Estimate height
                var estimatedHeight: CGFloat = 30 // section title + padding
                for (_, value) in nonEmpty {
                    let textHeight = (value as NSString).boundingRect(
                        with: CGSize(width: contentWidth - 24, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: valueFont],
                        context: nil
                    ).height
                    estimatedHeight += 16 + textHeight + 4 // label + value + spacing
                }
                estimatedHeight += 12 // bottom padding

                beginPageIfNeeded(requiredSpace: min(estimatedHeight, 120))

                y += 8

                // Section background
                let bgRect = CGRect(x: margin, y: y, width: contentWidth, height: estimatedHeight)
                let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 10)
                sectionBg.setFill()
                bgPath.fill()

                y += 10

                // Section title
                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: sectionTitleFont,
                    .foregroundColor: brandBlue
                ]
                (title as NSString).draw(
                    at: CGPoint(x: margin + 12, y: y),
                    withAttributes: titleAttr
                )
                y += 22

                // Fields
                for (label, value) in nonEmpty {
                    if y + 30 > pageHeight - margin {
                        beginPageIfNeeded()
                    }

                    let labelAttr: [NSAttributedString.Key: Any] = [
                        .font: labelFont,
                        .foregroundColor: UIColor.secondaryLabel
                    ]
                    (label.uppercased() as NSString).draw(
                        at: CGPoint(x: margin + 12, y: y),
                        withAttributes: labelAttr
                    )
                    y += 14

                    let valueAttr: [NSAttributedString.Key: Any] = [
                        .font: valueFont,
                        .foregroundColor: UIColor.label
                    ]
                    let valueRect = CGRect(x: margin + 12, y: y, width: contentWidth - 24, height: .greatestFiniteMagnitude)
                    let drawnRect = (value as NSString).boundingRect(
                        with: valueRect.size,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: valueAttr,
                        context: nil
                    )
                    (value as NSString).draw(
                        with: CGRect(origin: valueRect.origin, size: drawnRect.size),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: valueAttr,
                        context: nil
                    )
                    y += drawnRect.height + 8
                }

                y += 4
            }

            // ==================== PAGE 1 ====================
            beginPageIfNeeded()

            // Header bar
            let headerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 70)
            brandBlue.setFill()
            UIBezierPath(rect: headerRect).fill()

            let appTitleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            ("MyPass" as NSString).draw(at: CGPoint(x: margin, y: 14), withAttributes: appTitleAttr)

            let taglineAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            ("Support Card" as NSString).draw(at: CGPoint(x: margin, y: 36), withAttributes: taglineAttr)

            y = 86

            // Child name + initials circle
            let initials: String = {
                let parts = cardData.childName.split(separator: " ")
                if parts.count >= 2 {
                    return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
                }
                return String(cardData.childName.prefix(2)).uppercased()
            }()

            let circleSize: CGFloat = 48
            let circleRect = CGRect(x: margin, y: y, width: circleSize, height: circleSize)
            let circlePath = UIBezierPath(ovalIn: circleRect)
            UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1).setFill()
            circlePath.fill()

            let initialsAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let initialsSize = (initials as NSString).size(withAttributes: initialsAttr)
            (initials as NSString).draw(
                at: CGPoint(
                    x: circleRect.midX - initialsSize.width / 2,
                    y: circleRect.midY - initialsSize.height / 2
                ),
                withAttributes: initialsAttr
            )

            // Name
            let nameAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: deepBlue
            ]
            let displayName = cardData.childName.isEmpty ? "Unnamed" : cardData.childName
            (displayName as NSString).draw(
                at: CGPoint(x: margin + circleSize + 14, y: y + 2),
                withAttributes: nameAttr
            )

            // DOB & diagnosis
            var infoY = y + 28
            if !cardData.dateOfBirth.isEmpty {
                let dobAttr: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: UIColor.secondaryLabel]
                ("Born: \(cardData.dateOfBirth)" as NSString).draw(
                    at: CGPoint(x: margin + circleSize + 14, y: infoY),
                    withAttributes: dobAttr
                )
                infoY += 16
            }
            if !cardData.diagnosis.isEmpty {
                let diagAttr: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: brandBlue]
                (cardData.diagnosis as NSString).draw(
                    at: CGPoint(x: margin + circleSize + 14, y: infoY),
                    withAttributes: diagAttr
                )
            }

            y += circleSize + 20

            // Divider
            UIColor.separator.setStroke()
            let divider = UIBezierPath()
            divider.move(to: CGPoint(x: margin, y: y))
            divider.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            divider.lineWidth = 0.5
            divider.stroke()
            y += 12

            // --- Sections ---
            drawSection(title: "Communication", fields: [
                ("Method", cardData.communicationMethod),
                ("Notes", cardData.communicationNotes),
            ])

            drawSection(title: "Sensory Profile", fields: [
                ("Sensory Seeks", cardData.sensorySeeks),
                ("Sensory Avoids", cardData.sensoryAvoids),
                ("Stimming Behaviours", cardData.stimmingBehaviours),
            ])

            drawSection(title: "Behaviour & Regulation", fields: [
                ("Signs of Overwhelm", cardData.signsOfOverwhelm),
                ("Meltdown Support", cardData.meltdownSupport),
                ("Shutdown Support", cardData.shutdownSupport),
                ("Calming Strategies", cardData.calmingStrategies),
                ("Elopement Risk", cardData.elopementRisk),
            ])

            drawSection(title: "Routines & Interests", fields: [
                ("Routine Needs", cardData.routineNeeds),
                ("Special Interests", cardData.specialInterests),
                ("Safe Foods", cardData.safeFoods),
            ])

            drawSection(title: "Medical", fields: [
                ("Medications", cardData.medications),
                ("Allergies", cardData.allergies),
                ("Other Medical", cardData.otherMedical),
            ])

            drawSection(title: "Emergency Contact", fields: [
                ("Name", cardData.emergencyContactName),
                ("Relationship", cardData.emergencyContactRelationship),
                ("Phone", cardData.emergencyContactPhone),
            ])

            if !cardData.additionalNotes.isEmpty {
                drawSection(title: "Additional Notes", fields: [
                    ("Notes", cardData.additionalNotes),
                ])
            }

            // Footer on current page
            let footer = "Generated from MyPass — keep in a safe place."
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.tertiaryLabel
            ]
            let footerSize = (footer as NSString).size(withAttributes: footerAttr)
            (footer as NSString).draw(
                at: CGPoint(x: pageWidth / 2 - footerSize.width / 2, y: pageHeight - margin + 10),
                withAttributes: footerAttr
            )
        }
    }
}
