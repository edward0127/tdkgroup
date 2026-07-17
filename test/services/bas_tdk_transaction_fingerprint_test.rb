require "test_helper"

class BasTdkTransactionFingerprintTest < ActiveSupport::TestCase
  test "extracts conservative transfer POS and payroll template keys" do
    assert_equal [ "fast_transfer_from" ], fingerprint("Fast Transfer From ADYEN AUSTRALIA sweep").template_keys
    assert_equal [ "fast_transfer_to" ], fingerprint("Fast Transfer To Supplier Pty Ltd invoice 42").template_keys
    assert_equal [ "pos" ], fingerprint("POS 22248700 30 JUN").template_keys
    assert_equal [ "weekly_pay" ], fingerprint("Transfer To Employee NetBank weekly pay").template_keys
    assert_equal [ "staff_wages" ], fingerprint("Multiple Transfer NetBank staff wages").template_keys
    assert_equal [ "staff_wages" ], fingerprint("Employee wages batch").template_keys
  end

  test "requires fast transfer and POS templates to start the description" do
    assert_empty fingerprint("Receipt for a fast transfer from the customer").template_keys
    assert_empty fingerprint("Merchant memo POS 22248700").template_keys
  end

  test "does not generalize validation micro deposits as ordinary transfers" do
    result = fingerprint("Fast Transfer From Employment Hero Micro deposit for account verification")

    refute_includes result.template_keys, "fast_transfer_from"
  end

  test "extracts stable strong brand keys despite branch and transaction references" do
    samples = {
      "bp" => [
        "BP AA DONCASTER 0056 DONCASTER AU Card xx4534",
        "BP BUNDOORA 7352 BUNDOORA AU"
      ],
      "doordash" => [
        "Direct Credit 507141 DoorDashMilduraN DoorDashM_UiqFomoy",
        "DOOR DASH order 998877",
        "Direct Credit 507141 DoorDashM_UiqFomoy"
      ],
      "adyen" => [
        "Fast Transfer From ADYEN AUSTRALIA EXT BAL SWEEP SWPE42WS322322235PKGHTM"
      ],
      "uber" => [
        "Direct Credit 480255 UBER BV Store ID 123 TXN I"
      ],
      "origin_energy" => [
        "ORIGIN ENERGY NetBank BPAY 130112 origin gas"
      ]
    }

    samples.each do |expected_key, descriptions|
      descriptions.each do |description|
        assert_includes fingerprint(description).merchant_keys, expected_key
      end
    end
  end

  test "recognizes additional exact strong brands without assigning accounting meaning" do
    result = fingerprint("OFFICEWORKS order paid via ADYEN AUSTRALIA")

    assert_equal [ "adyen", "officeworks" ], result.merchant_keys
    assert_empty result.template_keys
  end

  test "extracts client-specific bank memo and counterparty identities without assigning a category" do
    kiki = fingerprint("Transfer To WENG CAIMING CommBank App Kiki")
    supplier = fingerprint("Transfer To Mallee Meats CommBank App Mallee Meats")
    rent = fingerprint("Transfer to other Bank NetBank Shop Rent April")
    shares = fingerprint("Transfer To Masooma Haidary CommBank App Masooma Shares")

    assert_includes kiki.merchant_keys, "commbank_app_head:kiki"
    assert_includes supplier.merchant_keys, "transfer_party:mallee meats"
    assert_includes supplier.merchant_keys, "mallee_meats"
    assert_includes rent.merchant_keys, "shop_rent"
    assert_includes rent.merchant_keys, "netbank_memo_head:shop rent"
    assert_includes shares.merchant_keys, "commbank_app_tokens:masooma shares"
    assert_includes fingerprint("Transfer to xx3022 CommBank app Shares Masooma").merchant_keys,
      "commbank_app_tokens:masooma shares"
  end

  test "does not confuse BP with BPAY or match brand fragments inside unrelated words" do
    assert_empty fingerprint("NetBank BPAY 75556 tax payment").merchant_keys
    assert_empty fingerprint("A dashboard subscription and uberisation report").merchant_keys
  end

  test "returns empty stable collections for blank or invalid input" do
    blank = fingerprint(nil)
    invalid = fingerprint("Bad\xFF text".b)

    assert_equal [], blank.template_keys
    assert_equal [], blank.merchant_keys
    assert_equal [], invalid.template_keys
    assert_equal [], invalid.merchant_keys
  end

  private

  def fingerprint(description)
    BasTdk::TransactionFingerprint.call(description)
  end
end
