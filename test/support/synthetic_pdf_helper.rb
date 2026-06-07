module SyntheticPdfHelper
  def synthetic_pdf(text)
    escaped_lines = text.to_s.lines.map do |line|
      line.chomp.gsub("\\", "\\\\").gsub("(", "\\(").gsub(")", "\\)")
    end
    operations = escaped_lines.map.with_index do |line, index|
      prefix = index.zero? ? "" : "0 -14 Td "
      "#{prefix}(#{line}) Tj"
    end.join(" ")
    stream = "BT /F1 10 Tf 50 750 Td #{operations} ET"
    objects = [
      "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
      "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
      "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
      "4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n",
      "5 0 obj << /Length #{stream.bytesize} >> stream\n#{stream}\nendstream endobj\n"
    ]

    pdf = "%PDF-1.4\n"
    offsets = [ 0 ]
    objects.each do |object|
      offsets << pdf.bytesize
      pdf << object
    end

    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n"
    pdf << "0000000000 65535 f \n"
    offsets.drop(1).each { |offset| pdf << "%010d 00000 n \n" % offset }
    pdf << "trailer << /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
    pdf
  end

  def attach_synthetic_pdf(document, text:, filename: "synthetic_bank_statement.pdf")
    document.file.attach(
      io: StringIO.new(synthetic_pdf(text)),
      filename: filename,
      content_type: "application/pdf"
    )
  end
end
