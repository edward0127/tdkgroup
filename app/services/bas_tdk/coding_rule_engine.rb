require "bigdecimal"

module BasTdk
  class CodingRuleEngine
    RULESET_VERSION = "ato-conservative-2026-07-v5".freeze
    TAXABLE_CAVEAT = "Confirm a valid tax invoice, supplier GST registration and business-use percentage before accepting the GST amount.".freeze
    TAXABLE_MERCHANT_FEE_PATTERN = /\b(?:merchant (?:card|service) fees?|card processing fees?)\b/i

    Suggestion = Struct.new(
      :category,
      :gst_amount,
      :gst_treatment,
      :category_confidence,
      :gst_confidence,
      :category_review_required,
      :gst_review_required,
      :warning_codes,
      :explanation,
      :rule_id,
      keyword_init: true
    )

    NO_GST_RULES = [
      [ "ato_payment", /\b(?:australian taxation office|tax(?:ation)? office payments?|ato(?:\s+direct)?|integrated client account|activity statement|bas payment|tax refund)\b/i, "Tax payments", "ATO payments and tax refunds do not themselves carry GST." ],
      [ "employee_wages", /\b(?:payroll|salary|salaries|wage|wages|wages batch)\b/i, "Wages & salaries", "Employee wages do not carry GST; confirm this is an employee payment rather than a contractor invoice." ],
      [ "superannuation", /\b(?:superannuation|super guarantee|super clearing|superfund|super fund|staff super|super (?:payment|contribution))\b/i, "Superannuation", "Employer superannuation contributions do not themselves carry GST." ],
      [ "bank_interest", /\b(?:loan interest|interest charge|interest paid|bank interest|credit interest|debit interest)\b/i, "Interest", "Bank and loan interest is generally input taxed and has no GST credit." ],
      [ "bank_fee", /\b(?:monthly (?:account|plan) fee|bank fee|account fee|account keeping fee|overdraft fee|dishonou?r fee)\b/i, "Bank fees", "Bank fees and charges generally do not include claimable GST." ],
      [ "explicit_transfer", /\b(?:internal transfer|transfer between accounts|own account transfer|inter-account transfer)\b/i, "Transfers", "An internal transfer is outside GST; confirm both sides belong to this business." ],
      [ "explicit_loan_principal", /\b(?:loan principal|principal repayment|loan advance|loan drawdown)\b/i, "Loan principal", "Loan principal does not carry GST; split any interest or fees using the lender statement." ]
    ].freeze

    TAXABLE_EXPENSE_RULES = [
      [ "software", /\b(?:software|subscription|microsoft|adobe|xero|myob|quickbooks|saas|web hosting|domain renewal)\b/i, "Software & subscriptions" ],
      [ "printing_stationery", /\b(?:menu printing|commercial printing)\b/i, "Stationery" ],
      [ "office_expenses", /\b(?:officeworks|stationery|office supplies|printer ink|toner|printing|print shop)\b/i, "Office expenses" ],
      [ "packaging", /\b(?:packaging|packging|packing supplies?)\b/i, "Packaging" ],
      [ "equipment", /\b(?:harvey norman|computer equipment|office furniture|appliance replacement)\b/i, "Equipment & assets" ],
      [ "fuel", /\b(?:fuel|petrol|diesel|bp service|shell service|ampol|caltex)\b/i, "Motor vehicle expenses" ],
      [ "parking", /\b(?:parking|car park|secure parking|wilson parking)\b/i, "Parking" ],
      [ "phone_internet", /\b(?:telephone|mobile plan|internet|broadband|telstra|optus|vodafone|nbn)\b/i, "Telephone & internet" ],
      [ "repairs", /\b(?:repair|repairs|maintenance|servicing)\b/i, "Repairs & maintenance" ],
      [ "advertising", /\b(?:advertising|facebook ads|meta ads|google ads|marketing campaign)\b/i, "Advertising & marketing" ],
      [ "freight", /\b(?:courier|postage|post shop|freight|australia post|fedex|dhl)\b/i, "Postage & freight" ],
      [ "utilities", /\b(?:electricity|energy bill|gas bill)\b/i, "Utilities" ]
    ].freeze

    UNCERTAIN_CATEGORY_RULES = [
      [ "uncertain_retailer", /(?:\bwoolworths\b|\bsq\W+minton\b)/i, "The transaction description does not identify what was purchased, and prior coding is not reliable enough to assign a Category automatically." ]
    ].freeze

    VERIFIED_CATEGORY_RULES = [
      [ "replacement", /\bkmart\b/i, "Replacement" ]
    ].freeze

    UNSAFE_GST_RULES = [
      [ "mixed_retailer", /\b(?:supermarket|grocer(?:y|ies)?|groc|woolworths|coles|aldi|costco|pharmacy|chemist|department store)\b/i, "General expenses", "This supplier can sell both taxable and GST-free items; use the tax invoice GST amount." ],
      [ "insurance_registration", /\b(?:insurance|registration|rego|vic roads|vicroads|service nsw|transport accident)\b/i, "Insurance & registration", "Insurance and registration payments can contain GST, stamp duty and government-fee components." ],
      [ "staff_amenities", /\b(?:pizza for staff|staff (?:food|lunch|meal))\b/i, "Staff amenities", "GST and deductibility can depend on business purpose, FBT treatment and the supporting tax invoice." ],
      [ "meals_entertainment", /\b(?:restaurant|cafe|coffee|meal|meals|pizza|staff (?:food|lunch)|entertainment|ubereats|uber eats|doordash|menulog)\b/i, "Meals & entertainment", "GST entitlement can depend on business purpose, income-tax deductibility and FBT treatment." ],
      [ "rent_property", /\b(?:rent|rental|lease|property|real estate|body corporate|strata)\b/i, "Rent & property", "Residential, commercial and property transactions can have different GST treatment." ],
      [ "international", /\b(?:international|foreign currency|overseas|customs|import duty|usd|eur|gbp|nzd)\b/i, "International expenses", "Australian GST cannot be inferred from an overseas or import bank transaction." ],
      [ "water_supply", /\b(?:water usage|water supply|water bill)\b/i, "Utilities", "Water charges can include GST-free supplies and taxable service components; use the supplier invoice GST amount." ]
    ].freeze

    def initialize(description:, amount:)
      @description = description.to_s
      @amount = decimal(amount)
    end

    def call
      taxable_merchant_fee_suggestion || no_gst_suggestion || uncertain_category_suggestion || verified_category_suggestion || unsafe_gst_suggestion || taxable_expense_suggestion || unmatched_suggestion
    end

    private

    def taxable_merchant_fee_suggestion
      return unless @amount&.nonzero? && @description.match?(TAXABLE_MERCHANT_FEE_PATTERN)

      suggestion(
        category: "Merchant fees",
        gst_amount: (@amount / 11).round(2),
        gst_treatment: "taxable",
        category_confidence: 82.0,
        gst_confidence: 70.0,
        warning_codes: [ "rule_suggestion_requires_review", "tax_invoice_required", "merchant_service_fee" ],
        explanation: "This looks like a merchant service or card-processing fee adjustment. #{TAXABLE_CAVEAT}",
        rule_id: "merchant_service_fee"
      )
    end

    def no_gst_suggestion
      match = NO_GST_RULES.find { |_id, pattern, _category, _explanation| @description.match?(pattern) }
      return unless match

      rule_id, _pattern, category, explanation = match
      suggestion(
        category: category,
        gst_amount: BigDecimal("0"),
        gst_treatment: rule_id.in?(%w[bank_interest bank_fee]) ? "input_taxed" : "bas_excluded",
        category_confidence: 90.0,
        gst_confidence: 90.0,
        warning_codes: [ "rule_suggestion_requires_review", rule_id ],
        explanation: explanation,
        rule_id: rule_id
      )
    end

    def unsafe_gst_suggestion
      match = UNSAFE_GST_RULES.find { |_id, pattern, _category, _explanation| @description.match?(pattern) }
      return unless match

      rule_id, _pattern, category, explanation = match
      suggestion(
        category: category,
        gst_amount: nil,
        gst_treatment: "needs_review",
        category_confidence: 72.0,
        gst_confidence: 0.0,
        warning_codes: [ "rule_suggestion_requires_review", "mixed_or_unsafe_gst", rule_id ],
        explanation: explanation,
        rule_id: rule_id
      )
    end

    def uncertain_category_suggestion
      match = UNCERTAIN_CATEGORY_RULES.find { |_id, pattern, _explanation| @description.match?(pattern) }
      return unless match

      rule_id, _pattern, explanation = match
      suggestion(
        category: nil,
        gst_amount: nil,
        gst_treatment: "needs_review",
        category_confidence: 0.0,
        gst_confidence: 0.0,
        warning_codes: [ "category_unclassified", "mixed_or_unsafe_gst", rule_id ],
        explanation: explanation,
        rule_id: rule_id
      )
    end

    def verified_category_suggestion
      return unless @amount&.nonzero?

      match = VERIFIED_CATEGORY_RULES.find { |_id, pattern, _category| @description.match?(pattern) }
      return unless match

      rule_id, _pattern, category = match
      suggestion(
        category: category,
        gst_amount: (@amount / 11).round(2),
        gst_treatment: "taxable",
        category_confidence: 85.0,
        gst_confidence: 65.0,
        warning_codes: [ "rule_suggestion_requires_review", "tax_invoice_required", rule_id ],
        explanation: "This merchant was verified against the client's coding corrections. #{TAXABLE_CAVEAT}",
        rule_id: rule_id
      )
    end

    def taxable_expense_suggestion
      return unless @amount&.negative?

      match = TAXABLE_EXPENSE_RULES.find { |_id, pattern, _category| @description.match?(pattern) }
      return unless match

      rule_id, _pattern, category = match
      suggestion(
        category: category,
        gst_amount: (@amount / 11).round(2),
        gst_treatment: "taxable",
        category_confidence: 78.0,
        gst_confidence: 65.0,
        warning_codes: [ "rule_suggestion_requires_review", "tax_invoice_required", rule_id ],
        explanation: "This looks like a usually taxable business expense. #{TAXABLE_CAVEAT}",
        rule_id: rule_id
      )
    end

    def unmatched_suggestion
      suggestion(
        category: nil,
        gst_amount: nil,
        gst_treatment: "unknown",
        category_confidence: 0.0,
        gst_confidence: 0.0,
        warning_codes: [ "category_unclassified", "gst_unclassified" ],
        explanation: "No reliable previous-quarter match or conservative coding rule was found. Review this transaction manually.",
        rule_id: "unmatched"
      )
    end

    def suggestion(**attributes)
      Suggestion.new(
        **attributes,
        category_review_required: true,
        gst_review_required: true
      )
    end

    def decimal(value)
      return value if value.is_a?(BigDecimal)

      text = value.to_s.strip
      return if text.blank?

      negative = text.match?(/\A\(.*\)\z/) || text.end_with?("-")
      normalized = text.gsub(/[,$\s()]/, "").sub(/-\z/, "")
      return unless normalized.match?(/\A[+-]?\d+(?:\.\d+)?\z/)

      result = BigDecimal(normalized)
      negative ? -result.abs : result
    rescue ArgumentError
      nil
    end
  end
end
