namespace :tdk do
  namespace :content_parity do
    desc "Dry-run the original TDK website content parity sync"
    task dry_run: :environment do
      TdkContentParitySync.new(dry_run: true).call
    end

    desc "Apply the approved original TDK website content parity sync"
    task apply: :environment do
      TdkContentParitySync.new(dry_run: false).call
    end
  end
end
