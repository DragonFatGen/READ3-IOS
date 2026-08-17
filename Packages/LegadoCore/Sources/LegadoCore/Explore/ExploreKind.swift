public struct ExploreKind: Codable, Equatable, Sendable {
    public let title: String
    public let url: String?
    public let style: Style?

    public init(title: String, url: String? = nil, style: Style? = nil) {
        self.title = title
        self.url = url
        self.style = style
    }

    public struct Style: Codable, Equatable, Sendable {
        public var layoutFlexGrow: Double
        public var layoutFlexShrink: Double
        public var layoutAlignSelf: String
        public var layoutFlexBasisPercent: Double
        public var layoutWrapBefore: Bool

        public init(
            layoutFlexGrow: Double = 0,
            layoutFlexShrink: Double = 1,
            layoutAlignSelf: String = "auto",
            layoutFlexBasisPercent: Double = -1,
            layoutWrapBefore: Bool = false
        ) {
            self.layoutFlexGrow = layoutFlexGrow
            self.layoutFlexShrink = layoutFlexShrink
            self.layoutAlignSelf = layoutAlignSelf
            self.layoutFlexBasisPercent = layoutFlexBasisPercent
            self.layoutWrapBefore = layoutWrapBefore
        }

        private enum CodingKeys: String, CodingKey {
            case layoutFlexGrow = "layout_flexGrow"
            case layoutFlexShrink = "layout_flexShrink"
            case layoutAlignSelf = "layout_alignSelf"
            case layoutFlexBasisPercent = "layout_flexBasisPercent"
            case layoutWrapBefore = "layout_wrapBefore"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            layoutFlexGrow = try container.decodeIfPresent(Double.self, forKey: .layoutFlexGrow) ?? 0
            layoutFlexShrink = try container.decodeIfPresent(Double.self, forKey: .layoutFlexShrink) ?? 1
            layoutAlignSelf = try container.decodeIfPresent(String.self, forKey: .layoutAlignSelf) ?? "auto"
            layoutFlexBasisPercent = try container.decodeIfPresent(
                Double.self,
                forKey: .layoutFlexBasisPercent
            ) ?? -1
            layoutWrapBefore = try container.decodeIfPresent(Bool.self, forKey: .layoutWrapBefore) ?? false
        }
    }
}
