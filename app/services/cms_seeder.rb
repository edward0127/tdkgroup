require "stringio"

class CmsSeeder
  PAGES = [
    {
      slug: "home",
      template: "home",
      show_in_nav: true,
      show_in_footer: false,
      sort_order: 10,
      en: {
        title: "TDK Group Pty Ltd",
        seo_title: "TDK Group Pty Ltd | Accounting, Taxation and Business Advisory",
        seo_description: "TDK Group Pty Ltd provides accounting, taxation, business advisory and immigration-related accounting services in Surrey Hills, Victoria.",
        content: {
          hero: {
            eyebrow: "CPA accounting and advisory",
            title: "Expert taxation and consulting for businesses, families and investors.",
            lead: "TDK Group Pty Ltd helps clients navigate tax, reporting, business decisions and migration-related financial requirements with practical, tailored advice.",
            primary_label: "Contact TDK",
            primary_slug: "contact-us",
            secondary_label: "Explore services",
            secondary_slug: "our-services",
            stats: [
              { value: "20+ years", label: "senior accounting experience" },
              { value: "CPA", label: "professional standards" },
              { value: "EN / 中文", label: "bilingual support" }
            ]
          },
          sections: [
            {
              kind: "intro",
              eyebrow: "Trusted by clients",
              title: "Accounting advice with commercial context.",
              body: [
                "We are more than an accounting firm. We work as strategic partners for clients who need clear reporting, compliant tax outcomes and practical business support.",
                "Our work spans individuals, professional practices, retail, manufacturing, construction, property, importing, exporting and overseas investment."
              ]
            },
            {
              kind: "cards",
              eyebrow: "Core services",
              title: "Comprehensive services, tailored for success.",
              items: [
                { title: "Tax services", body: "Individual and business tax returns, tax planning, BAS, GST and ATO audit support.", slug: "our-services/tax-services" },
                { title: "Business accounting", body: "Bookkeeping, financial statements, PAYG, superannuation, registrations and accounting systems.", slug: "our-services/business-services" },
                { title: "Management consulting", body: "Business structures, process improvement, risk reviews, feasibility studies and transaction advice.", slug: "our-services/management-consulting" },
                { title: "Immigration accounting", body: "Financial reports, accounts and audit support for business and skilled migration requirements.", slug: "our-services/immigration-related-accounting-services" }
              ]
            },
            {
              kind: "split",
              eyebrow: "Professional assurance",
              title: "Built around technical expertise and client confidentiality.",
              body: [
                "TDK Group combines CPA, IPA, registered tax agent, SMSF auditor and ASIC agent capability with a practical understanding of Australian business conditions.",
                "Clients receive clear advice, responsive communication and support designed around their goals."
              ],
              bullets: [ "Taxation and compliance", "Business advisory and reporting", "Migration-related financial documentation", "Bilingual client support" ]
            },
            {
              kind: "cta",
              title: "Ready to discuss your accounting needs?",
              body: "Call 03 9890 4988 or send an enquiry and the team will respond promptly.",
              label: "Make an enquiry",
              slug: "contact-us"
            }
          ]
        }
      },
      zh: {
        title: "黄金会计师事务所",
        seo_title: "黄金会计师事务所 | 会计、税务与商业咨询",
        seo_description: "黄金会计师事务所为个人和企业提供税务、会计、商业咨询及移民相关会计服务。",
        content: {
          hero: {
            eyebrow: "注册会计师会计与咨询服务",
            title: "为企业、家庭与投资者提供专业税务和咨询支持。",
            lead: "TDK Group Pty Ltd 专注于定制财务策略和个性化咨询，协助客户处理税务、报表、商业决策及移民相关财务要求。",
            primary_label: "联系我们",
            primary_slug: "contact-us",
            secondary_label: "了解服务",
            secondary_slug: "our-services",
            stats: [
              { value: "20+ 年", label: "资深会计经验" },
              { value: "CPA", label: "专业标准" },
              { value: "EN / 中文", label: "双语服务" }
            ]
          },
          sections: [
            {
              kind: "intro",
              eyebrow: "值得信赖",
              title: "结合专业会计能力与商业视角。",
              body: [
                "我们不仅是一家会计事务所，更是客户实现稳健发展的战略合作伙伴，提供清晰报表、合规税务及实用商业支持。",
                "我们的客户覆盖专业服务、零售、制造、建筑、房地产、进出口贸易及海外投资等行业。"
              ]
            },
            {
              kind: "cards",
              eyebrow: "核心服务",
              title: "全面服务，为成功量身定制。",
              items: [
                { title: "税务服务", body: "个人和企业税务申报、税务规划、BAS、GST及ATO调查协助。", slug: "our-services/tax-services" },
                { title: "商业会计服务", body: "记账、财务报表、PAYG、养老金、商业注册及会计系统支持。", slug: "our-services/business-services" },
                { title: "管理咨询", body: "企业架构、流程优化、风险评估、可行性研究及企业买卖咨询。", slug: "our-services/management-consulting" },
                { title: "移民相关会计服务", body: "为商业及技术移民申请准备财务报表、账户及审计支持。", slug: "our-services/immigration-related-accounting-services" }
              ]
            },
            {
              kind: "split",
              eyebrow: "专业保障",
              title: "以技术能力和客户保密为核心。",
              body: [
                "TDK Group 结合 CPA、IPA、注册税务代理、SMSF 审计师及 ASIC 代理资质，深入理解澳大利亚商业环境。",
                "我们为客户提供清晰建议、及时沟通和围绕目标设计的专业支持。"
              ],
              bullets: [ "税务与合规", "商业咨询与报表", "移民相关财务文件", "中英文双语服务" ]
            },
            {
              kind: "cta",
              title: "需要讨论您的会计需求？",
              body: "请致电 03 9890 4988，或提交咨询表格，我们会尽快回复。",
              label: "提交咨询",
              slug: "contact-us"
            }
          ]
        }
      }
    },
    {
      slug: "about-us",
      template: "standard",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: 20,
      en: {
        title: "About Us",
        seo_title: "About TDK Group Pty Ltd",
        seo_description: "Learn about TDK Group Pty Ltd, a boutique accounting and consulting firm in Surrey Hills.",
        content: {
          hero: {
            eyebrow: "About TDK Group",
            title: "A boutique accounting firm built on professionalism, integrity and client focus.",
            lead: "Founded to deliver exceptional accounting and consulting services, TDK Group has grown into a trusted advisory partner for individuals and businesses."
          },
          sections: [
            {
              kind: "intro",
              title: "Our history",
              body: [
                "TDK Group was established by Tom Huang, a Certified Practicing Accountant and ASIC agent, with a passion for empowering clients to achieve financial success.",
                "From humble beginnings as a small firm serving local businesses, the practice has expanded its expertise while maintaining personal, attentive service."
              ]
            },
            {
              kind: "cards",
              title: "Industries we serve",
              items: [
                { title: "Professional services", body: "Doctors, lawyers and specialist service firms." },
                { title: "Retail and hospitality", body: "Wholesale, retail, restaurant and hospitality clients." },
                { title: "Construction and property", body: "Builders, designers, property investors and developers." },
                { title: "Trade and manufacturing", body: "Import, export and manufacturing businesses." }
              ]
            },
            {
              kind: "split",
              title: "Our commitment to excellence",
              body: [
                "Our services are grounded in technical expertise, ethical standards and a deep commitment to client success.",
                "We value long-term relationships and provide timely, reliable and proactive advice while protecting client confidentiality."
              ],
              bullets: [ "CPA professional capability", "Registered tax agent support", "ASIC agent services", "Practical advisory experience" ]
            }
          ]
        }
      },
      zh: {
        title: "公司简介",
        seo_title: "关于黄金会计师事务所",
        seo_description: "了解黄金会计师事务所，一家位于 Surrey Hills 的精品会计与咨询事务所。",
        content: {
          hero: {
            eyebrow: "关于 TDK Group",
            title: "以专业、诚信和客户为中心的精品会计事务所。",
            lead: "秉承提供卓越会计与咨询服务的愿景，TDK Group 已发展成为个人和企业值得信赖的咨询伙伴。"
          },
          sections: [
            {
              kind: "intro",
              title: "发展历程",
              body: [
                "TDK Group 由注册执业会计师兼 ASIC 代理黄简先生创立，致力于帮助客户实现财务成功。",
                "从服务本地企业的小型事务所起步，我们不断拓展专业领域，同时保持细致、负责的客户服务。"
              ]
            },
            {
              kind: "cards",
              title: "服务行业",
              items: [
                { title: "专业服务", body: "医生、律师及其他专业服务机构。" },
                { title: "零售与餐饮", body: "批发、零售、餐饮及酒店业客户。" },
                { title: "建筑与房地产", body: "建筑商、设计师、房地产投资者及开发商。" },
                { title: "贸易与制造", body: "进出口贸易和制造业企业。" }
              ]
            },
            {
              kind: "split",
              title: "追求卓越",
              body: [
                "我们的服务建立在专业技术、职业道德和对客户成功的承诺之上。",
                "我们重视长期合作关系，提供及时、可靠、积极的建议，并严格保护客户信息。"
              ],
              bullets: [ "CPA 专业能力", "注册税务代理支持", "ASIC 代理服务", "实用商业咨询经验" ]
            }
          ]
        }
      }
    },
    {
      slug: "our-services",
      template: "services",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: 30,
      en: {
        title: "Our Services",
        seo_title: "Accounting, Taxation and Advisory Services | TDK Group",
        seo_description: "Explore TDK Group taxation, business accounting, management consulting and immigration-related accounting services.",
        content: {
          hero: {
            eyebrow: "Our services",
            title: "Professional services for every stage of business and personal finance.",
            lead: "We deliver tailored accounting, taxation and advisory solutions that support compliance, growth and confident decision-making."
          },
          sections: [
            {
              kind: "cards",
              title: "Services designed around your goals",
              items: [
                { title: "Taxation services", body: "Tax planning, returns, BAS, GST and ATO support for individuals and business entities.", slug: "our-services/tax-services" },
                { title: "Business accounting services", body: "Bookkeeping, financial statements, payroll-related reporting and accounting system implementation.", slug: "our-services/business-services" },
                { title: "Management consulting", body: "Structure planning, process optimisation, risk management and feasibility analysis.", slug: "our-services/management-consulting" },
                { title: "Immigration-related accounting", body: "Financial reporting and audit support for migration applications.", slug: "our-services/immigration-related-accounting-services" }
              ]
            }
          ]
        }
      },
      zh: {
        title: "我们的服务",
        seo_title: "会计、税务与咨询服务 | 黄金会计师事务所",
        seo_description: "了解黄金会计师事务所提供的税务、商业会计、管理咨询及移民相关会计服务。",
        content: {
          hero: {
            eyebrow: "我们的服务",
            title: "为企业和个人财务各阶段提供专业支持。",
            lead: "我们提供量身定制的会计、税务和咨询解决方案，帮助客户实现合规、增长和自信决策。"
          },
          sections: [
            {
              kind: "cards",
              title: "围绕您的目标设计的服务",
              items: [
                { title: "税务服务", body: "为个人和企业实体提供税务规划、税务申报、BAS、GST及ATO支持。", slug: "our-services/tax-services" },
                { title: "商业会计服务", body: "记账、财务报表、薪酬相关报告及会计系统实施。", slug: "our-services/business-services" },
                { title: "管理咨询", body: "企业架构规划、流程优化、风险管理及可行性分析。", slug: "our-services/management-consulting" },
                { title: "移民相关会计", body: "为移民申请提供财务报告和审计支持。", slug: "our-services/immigration-related-accounting-services" }
              ]
            }
          ]
        }
      }
    }
  ].freeze

  SERVICE_PAGES = [
    {
      slug: "our-services/tax-services",
      title_en: "Taxation Services",
      title_zh: "税务服务",
      lead_en: "Navigating the changing tax environment requires expertise and strategic planning.",
      lead_zh: "应对不断变化且复杂的税务环境需要专业知识与战略规划。",
      body_en: [
        "At TDK Group, we help individuals and businesses use tax laws and regulations effectively while maintaining compliance.",
        "Our tax services include tax planning and consulting, individual tax returns, company, trust, partnership and SMSF tax returns, BAS and GST reporting, indirect tax advice and assistance with ATO investigations or audits."
      ],
      body_zh: [
        "在 TDK Group，我们协助个人和企业有效理解并运用税法法规，在合规基础上实现财务目标。",
        "我们的税务服务包括税务规划与咨询、个人所得税申报、公司、信托、合伙企业及自管养老金基金税务申报、BAS 和 GST 申报、间接税建议，以及协助应对 ATO 调查与审计。"
      ]
    },
    {
      slug: "our-services/business-services",
      title_en: "Business Accounting Services",
      title_zh: "商业会计服务",
      lead_en: "Reliable accounting support helps your business operate efficiently and grow with confidence.",
      lead_zh: "可靠的会计支持能帮助企业高效运营并稳健成长。",
      body_en: [
        "We provide bookkeeping, financial statement preparation, accounting training and consulting, PAYG, superannuation and other reports.",
        "We also assist with trademark applications, WorkCover, business registrations and accounting systems such as Xero, MYOB and QuickBooks."
      ],
      body_zh: [
        "我们提供记账、财务报表编制、专业会计培训与咨询、PAYG、养老金及其他报告准备。",
        "我们也协助商标申请、WorkCover、商业与实体注册，以及 Xero、MYOB、QuickBooks 等会计系统的建立与优化。"
      ]
    },
    {
      slug: "our-services/management-consulting",
      title_en: "Management Consulting",
      title_zh: "管理咨询",
      lead_en: "The right operational and structural decisions shape the direction of business development.",
      lead_zh: "正确的运营与架构决策决定企业发展的方向。",
      body_en: [
        "We provide individual salary restructuring, business structure planning, process consulting, operational strategy, risk management, benchmarking and business reviews.",
        "Our advisory work also covers feasibility assessments, strategic advice and support for business purchases or sales."
      ],
      body_zh: [
        "我们提供个人薪资重组、企业架构规划、业务流程咨询、运营战略、风险管理、商业基准分析及业务审查。",
        "我们的咨询服务也涵盖可行性评估、综合战略建议，以及企业买卖过程中的价值与风险评估支持。"
      ]
    },
    {
      slug: "our-services/immigration-related-accounting-services",
      title_en: "Immigration Related Accounting Services",
      title_zh: "移民相关会计服务",
      lead_en: "Financial documentation for migration applications can be complex and time-sensitive.",
      lead_zh: "移民申请中的财务文件通常复杂且时间要求严格。",
      body_en: [
        "TDK Group provides tailored accounting support for individuals and businesses with migration needs.",
        "Services include preparation of business migration accounts, financial reports and account audits for business skilled migration and related visa requirements."
      ],
      body_zh: [
        "TDK Group 为有移民需求的个人和企业提供量身定制的会计支持。",
        "服务包括为商业技术移民及相关签证要求准备商业移民财务报表、财务报告和账户审计。"
      ]
    }
  ].freeze

  OTHER_PAGES = [
    {
      slug: "our-team",
      title_en: "Our Team",
      title_zh: "我们的团队",
      lead_en: "Meet the professional leadership behind TDK Group.",
      lead_zh: "了解 TDK Group 的专业负责人。",
      sections_en: [
        {
          kind: "profile",
          title: "Tom Huang",
          subtitle: "Director | CPA | SMSF Auditor | Tax Agent | ASIC Agent",
          body: [
            "Tom Huang is an experienced accounting professional with over 20 years of expertise.",
            "His qualifications include Certified Practicing Accountant, IPA Authorised Agent, SMSF Auditor, Registered Tax Agent and ASIC Agent.",
            "Tom has worked across multiple industries and provides clients with taxation, business structure, operational and investment-related advisory support."
          ],
          contact: "tomh@tdkgroup.com.au"
        }
      ],
      sections_zh: [
        {
          kind: "profile",
          title: "Tom Huang 黄简",
          subtitle: "董事 | 注册会计师 (CPA) | SMSF 审计师 | 税务代理 | ASIC 代理",
          body: [
            "Tom 是一位拥有超过 20 年会计经验的资深专业人士。",
            "其专业资质包括注册会计师、IPA 授权代理、SMSF 审计师、注册税务代理及 ASIC 代理。",
            "Tom 服务范围覆盖多个行业，为客户提供税务、企业架构、运营及投资相关咨询支持。"
          ],
          contact: "tomh@tdkgroup.com.au"
        }
      ]
    },
    {
      slug: "careers",
      title_en: "Careers",
      title_zh: "职业机会",
      lead_en: "Join a collaborative accounting and consulting team focused on client success.",
      lead_zh: "加入以客户成功为核心的协作型会计与咨询团队。",
      sections_en: [
        {
          kind: "split",
          title: "Why work with us?",
          body: [
            "TDK Group offers career development, a supportive culture, flexible work options and exposure to clients across diverse industries.",
            "For current roles, send your resume and cover letter to tomh@tdkgroup.com.au with the subject line [Position Name] Application."
          ],
          bullets: [ "Ongoing training", "Collaborative culture", "Hybrid work options", "Diverse client experience" ]
        },
        {
          kind: "intro",
          title: "Internship opportunities",
          body: [
            "We welcome university students studying accounting, finance, business or related fields.",
            "Send your resume to tomh@tdkgroup.com.au with the subject line [Name] Internship Application."
          ]
        }
      ],
      sections_zh: [
        {
          kind: "split",
          title: "为什么选择我们？",
          body: [
            "TDK Group 提供职业发展机会、支持性的团队文化、灵活工作安排，并让成员接触多个行业客户。",
            "如需申请职位，请将简历和求职信发送至 tomh@tdkgroup.com.au，邮件主题注明 [职位名称]申请。"
          ],
          bullets: [ "持续培训", "协作文化", "灵活工作方式", "多行业客户经验" ]
        },
        {
          kind: "intro",
          title: "实习机会",
          body: [
            "我们欢迎会计、金融、商业或相关专业的大学生申请实习。",
            "请将简历发送至 tomh@tdkgroup.com.au，邮件主题注明 [姓名] 实习申请。"
          ]
        }
      ]
    },
    {
      slug: "contact-us",
      title_en: "Contact Us",
      title_zh: "联系我们",
      lead_en: "Reach out to TDK Group and our team will get back to you promptly.",
      lead_zh: "请与 TDK Group 联系，我们的团队会尽快回复您的需求。",
      sections_en: [
        {
          kind: "contact",
          title: "Office details",
          details: [
            { label: "Phone", value: "03 9890 4988" },
            { label: "Email", value: "info@tdkgroup.com.au" },
            { label: "Office address", value: "1/550 Whitehorse Rd, Surrey Hills, VIC 3127" },
            { label: "Business hours", value: "Monday to Friday, 9:30 AM - 6:00 PM" }
          ]
        }
      ],
      sections_zh: [
        {
          kind: "contact",
          title: "联系方式",
          details: [
            { label: "电话", value: "03 9890 4988" },
            { label: "手机", value: "0426 969 868" },
            { label: "邮箱", value: "info@tdkgroup.com.au" },
            { label: "办公地址", value: "1/550 Whitehorse Rd, Surrey Hills, VIC 3127" },
            { label: "办公时间", value: "周一至周五 9:30 - 18:00，周六、周日请提前预约" }
          ]
        }
      ]
    }
  ].freeze

  ASSETS = [
    { key: "tdk-logo", file: "tdk-logo.jpg", content_type: "image/jpeg", alt_en: "TDK Group Pty Ltd logo", alt_zh: "黄金会计师事务所标志" },
    { key: "hero-handshake", file: "hero-handshake.jpg", content_type: "image/jpeg", alt_en: "Professional business handshake", alt_zh: "专业商务握手" },
    { key: "business-advisory", file: "business-advisory.jpg", content_type: "image/jpeg", alt_en: "Business advisory meeting", alt_zh: "商业咨询会议" },
    { key: "client-meeting", file: "client-meeting.jpg", content_type: "image/jpeg", alt_en: "International business and migration accounting support", alt_zh: "国际业务与移民相关会计支持" },
    { key: "office-documents", file: "office-documents.jpg", content_type: "image/jpeg", alt_en: "Financial reports and business documents", alt_zh: "财务报表与商业文件" },
    { key: "tax-service", file: "tax-service.jpg", content_type: "image/jpeg", alt_en: "Tax planning and accounting strategy", alt_zh: "税务规划与会计策略" },
    { key: "consulting-service", file: "consulting-service.jpg", content_type: "image/jpeg", alt_en: "Consulting meeting with financial charts", alt_zh: "财务图表咨询会议" },
    { key: "business-service", file: "business-service.jpg", content_type: "image/jpeg", alt_en: "Calculator and business accounting documents", alt_zh: "计算器与商业会计文件" },
    { key: "cpa-practice", file: "cpa-practice.png", content_type: "image/png", alt_en: "TDK professional practice banner", alt_zh: "TDK 专业资质横幅" },
    { key: "cpa-liability", file: "cpa-liability.png", content_type: "image/png", alt_en: "CPA Australia and professional standards credentials", alt_zh: "CPA Australia 与专业责任资质" }
  ].freeze

  def self.seed!
    new.seed!
  end

  def self.required_assets_attached?
    seeder = new
    ASSETS.all? do |asset_data|
      asset = CmsAsset.find_by(key: asset_data.fetch(:key))
      seeder.send(:asset_available?, asset)
    end
  end

  def seed!
    PAGES.each { |page| upsert_page(page) }
    SERVICE_PAGES.each { |page| upsert_service_page(page) }
    OTHER_PAGES.each { |page| upsert_other_page(page) }
    seed_assets!
  end

  private

  def seed_assets!
    ASSETS.each do |asset_data|
      asset = CmsAsset.find_or_initialize_by(key: asset_data.fetch(:key))
      asset.assign_attributes(
        alt_text_en: asset.alt_text_en.presence || asset_data.fetch(:alt_en),
        alt_text_zh: asset.alt_text_zh.presence || asset_data.fetch(:alt_zh)
      )

      asset_path = Rails.root.join("app/assets/images/tdk", asset_data.fetch(:file))
      if asset_path.exist? && !asset_available?(asset)
        asset.file.purge if asset.file.attached?
        asset.file.attach(
          io: StringIO.new(asset_path.binread),
          filename: asset_data.fetch(:file),
          content_type: asset_data.fetch(:content_type),
          identify: false
        )
      end

      asset.save!
    end
  end

  def asset_available?(asset)
    return false unless asset&.file&.attached?

    asset.file.blob.service.exist?(asset.file.blob.key)
  rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
    false
  end

  def upsert_page(page)
    cms_page = CmsPage.find_or_initialize_by(slug: page.fetch(:slug))
    cms_page.assign_attributes(page.slice(:template, :show_in_nav, :show_in_footer, :sort_order))
    cms_page.save!

    upsert_translation(cms_page, "en", page.fetch(:en))
    upsert_translation(cms_page, "zh", page.fetch(:zh))
  end

  def upsert_service_page(page)
    upsert_page(
      slug: page.fetch(:slug),
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 40 + SERVICE_PAGES.index(page).to_i,
      en: service_translation(page.fetch(:title_en), page.fetch(:lead_en), page.fetch(:body_en), "en"),
      zh: service_translation(page.fetch(:title_zh), page.fetch(:lead_zh), page.fetch(:body_zh), "zh")
    )
  end

  def upsert_other_page(page)
    upsert_page(
      slug: page.fetch(:slug),
      template: page.fetch(:slug) == "contact-us" ? "contact" : "standard",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: sort_order_for(page.fetch(:slug)),
      en: standard_translation(page.fetch(:title_en), page.fetch(:lead_en), page.fetch(:sections_en), "en"),
      zh: standard_translation(page.fetch(:title_zh), page.fetch(:lead_zh), page.fetch(:sections_zh), "zh")
    )
  end

  def service_translation(title, lead, body, locale)
    {
      title: title,
      seo_title: "#{title} | #{locale == 'zh' ? '黄金会计师事务所' : 'TDK Group'}",
      seo_description: lead,
      content: {
        hero: {
          eyebrow: locale == "zh" ? "专业服务" : "Professional service",
          title: title,
          lead: lead
        },
        sections: [
          {
            kind: "intro",
            title: title,
            body: body
          },
          {
            kind: "cta",
            title: locale == "zh" ? "需要专业支持？" : "Need specialist support?",
            body: locale == "zh" ? "联系我们，讨论适合您的服务方案。" : "Contact us to discuss the right service pathway for your needs.",
            label: locale == "zh" ? "联系我们" : "Contact us",
            slug: "contact-us"
          }
        ]
      }
    }
  end

  def standard_translation(title, lead, sections, locale)
    {
      title: title,
      seo_title: "#{title} | #{locale == 'zh' ? '黄金会计师事务所' : 'TDK Group'}",
      seo_description: lead,
      content: {
        hero: {
          eyebrow: locale == "zh" ? "TDK Group" : "TDK Group",
          title: title,
          lead: lead
        },
        sections: sections
      }
    }
  end

  def upsert_translation(cms_page, locale, data)
    translation = cms_page.translations.find_or_initialize_by(locale: locale)
    payload = data.fetch(:content)
    translation.assign_attributes(
      title: data.fetch(:title),
      seo_title: data[:seo_title],
      seo_description: data[:seo_description],
      published_json: translation.published_json.presence || payload,
      draft_json: translation.draft_json.presence || payload,
      published_at: translation.published_at || Time.current
    )
    translation.save!
  end

  def sort_order_for(slug)
    {
      "our-team" => 80,
      "careers" => 90,
      "contact-us" => 100
    }.fetch(slug, 50)
  end
end
