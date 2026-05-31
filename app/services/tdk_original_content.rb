class TdkOriginalContent
  def self.service_content(title:, lead:, list_title:, bullets:, cta:, label: "Contact Us")
    {
      hero: {
        title: title,
        lead: lead
      },
      sections: [
        {
          kind: "prose",
          title: list_title,
          bullets: bullets
        },
        {
          kind: "cta",
          title: cta,
          body: cta,
          label: label,
          slug: "contact-us"
        }
      ]
    }
  end

  private_class_method :service_content

  PAGES = [
    {
      slug: "home",
      template: "home",
      show_in_nav: true,
      show_in_footer: false,
      sort_order: 10,
      en: {
        title: "TDK Group Pty Ltd",
        seo_title: "TDK Group Pty Ltd – 黄金会计师事务所",
        seo_description: "TDK Group Pty Ltd specializes in tailored financial strategies and personalized consulting to help your business thrive.",
        content: {
          hero: {
            title: "Empowering Businesses with Expert Taxation and Consulting Services",
            lead: "TDK Group Pty Ltd specializes in tailored financial strategies and personalized consulting to help your business thrive. From bookkeeping to tax consulting, TDK Group provides expert solutions to streamline your business finances.",
            primary_label: "Explore our Services",
            primary_slug: "our-services"
          },
          sections: [
            {
              kind: "prose",
              title: "Trusted by Businesses and Individuals, Empowered by Expertise",
              body: [
                "We are more than an accounting firm — we are strategic partners in driving success. Trusted by professionals and businesses across diverse industries, we combine deep expertise with tailored solutions to deliver measurable impact. From tax and consulting to financial planning and auditing, we empower our clients to navigate complexity and achieve their goals with confidence."
              ]
            },
            {
              kind: "cards",
              title: "Comprehensive Services, Tailored for Success",
              body: [
                "At TDK Group Pty Ltd, we provide a wide range of professional services to support individuals and businesses in achieving their financial goals. Our offerings include:"
              ],
              items: [
                { title: "Tax Services:", body: "Individual and business tax returns, tax planning, BAS and GST preparation, and assistance with ATO investigations.", slug: "our-services/tax-services" },
                { title: "Business Services:", body: "Bookkeeping, financial statement preparation, PAYG and superannuation reporting, and business registration (e.g., company, trust, SMSF).", slug: "our-services/business-services" },
                { title: "Management Consulting:", body: "Business process optimization, risk management, operational strategy, and feasibility assessments for real estate and overseas investments.", slug: "our-services/management-consulting" },
                { title: "Immigration-Related Accounting:", body: "Preparation of financial reports and audits for business and skilled migration visas.", slug: "our-services/immigration-related-accounting-services" }
              ]
            },
            {
              kind: "prose",
              body: [
                "Explore our detailed services to learn how we can support your success at every stage."
              ]
            }
          ]
        }
      },
      zh: {
        title: "黄金会计师事务所",
        seo_title: "TDK Group Pty Ltd – 黄金会计师事务所",
        seo_description: "TDK Group Pty Ltd 专注于定制财务策略和个性化咨询，助力您的企业蓬勃发展。",
        content: {
          hero: {
            title: "赋能企业，提供专业会计与咨询服务",
            lead: "TDK Group Pty Ltd 专注于定制财务策略和个性化咨询，助力您的企业蓬勃发展。从记账到税务咨询，TDK Group 提供专业解决方案，简化您的企业财务管理。",
            primary_label: "探索我们的服务",
            primary_slug: "our-services"
          },
          sections: [
            {
              kind: "prose",
              title: "企业与个人信赖之选, 专业成就信心",
              body: [
                "我们不仅是一家会计事务所，更是助力成功的战略合作伙伴。备受各行业专业人士和企业的信赖，我们结合深厚的专业知识与量身定制的解决方案，创造显著的价值。从税务与咨询到财务规划和审计，我们帮助客户驾驭复杂性，自信地实现目标。"
              ]
            },
            {
              kind: "cards",
              title: "全面服务，为成功量身定制",
              body: [
                "在 TDK Group Pty Ltd，我们提供广泛的专业服务，帮助个人和企业实现其财务目标。我们的服务包括："
              ],
              items: [
                { title: "税务服务：", body: "个人和企业税务申报、税务规划、BAS 和 GST 准备，以及 ATO 调查协助。", slug: "our-services/tax-services" },
                { title: "商业服务：", body: "记账、财务报表编制、PAYG 和养老金（Superannuation）报告，以及商业注册（如公司、信托、自管养老金基金 SMSF）。", slug: "our-services/business-services" },
                { title: "管理咨询：", body: "业务流程优化、风险管理、运营战略，以及房地产和海外投资的可行性评估。", slug: "our-services/management-consulting" },
                { title: "移民相关会计服务：", body: "为商业和技术移民签证准备财务报告和审计服务。", slug: "our-services/immigration-related-accounting-services" }
              ]
            },
            {
              kind: "prose",
              body: [
                "探索我们的详细服务，了解我们如何在每个阶段支持您的成功。"
              ]
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
        seo_title: "About Us – TDK Group Pty Ltd",
        seo_description: "Founded with a vision to deliver exceptional accounting and consulting services, TDK Group Pty Ltd has grown into a trusted boutique firm.",
        content: {
          hero: {
            title: "About Us",
            lead: "Founded with a vision to deliver exceptional accounting and consulting services, TDK Group Pty Ltd has grown into a trusted boutique firm recognized for its professionalism, integrity, and client-focused approach. As Certified Practicing Accountants (CPA), members of the Institute of Public Accountants (IPA), and registered ASIC agents, we bring a wealth of expertise and industry recognition to every client we serve."
          },
          sections: [
            {
              kind: "prose",
              body: [
                "With years of experience, we have built a reputation for helping businesses and individuals navigate complex financial landscapes through tailored solutions that meet their unique needs. Our credentials and dedication to excellence ensure that every service we provide is grounded in both technical expertise and a deep commitment to our clients’ success."
              ]
            },
            {
              kind: "intro",
              title: "Our History",
              body: [
                "TDK Group was established by Tom Huang, a Certified Practicing Accountant (CPA) and ASIC agent, with a passion for empowering clients to achieve financial success. From our humble beginnings as a small firm serving local businesses, we have expanded our expertise to support clients across various industries, including professional services, retail, manufacturing, and real estate.",
                "Over the years, our team has embraced innovation and continued professional development to stay ahead in an ever-changing financial environment. This dedication ensures we deliver services that are both forward-thinking and grounded in proven methodologies."
              ]
            },
            {
              kind: "prose",
              title: "Our Services",
              body: [
                "We offer a comprehensive range of services, including:"
              ],
              bullets: [
                "– Tax Services: Individual and business tax returns, tax planning, BAS/GST preparation, and assistance with ATO investigations.",
                "– Accounting Services: Bookkeeping, financial reporting, and PAYG and superannuation preparation.",
                "– Management Consulting: Strategic advice, risk management, and business process optimization.",
                "– Immigration-related Accounting Services: Assistance with business and skilled immigration financial reporting."
              ]
            },
            {
              kind: "prose",
              body: [ "Learn more about our services" ]
            },
            {
              kind: "prose",
              title: "Industries We Serve",
              body: [
                "We proudly support clients across a diverse range of sectors, including:"
              ],
              bullets: [
                "– Professional services (e.g., doctors, lawyers)",
                "– Wholesale and retail",
                "– Catering and hospitality",
                "– Building construction and architectural design",
                "– Import/export and manufacturing",
                "– Real estate and property development"
              ]
            },
            {
              kind: "prose",
              title: "Our Commitment to Excellence",
              body: [
                "At TDK Group, we are driven by professional and ethical standards. With extensive industry knowledge and experience, we deliver timely, reliable, and proactive solutions, ensuring the confidentiality and success of every client. We take pride in fostering long-term relationships, understanding that our clients’ success is our success."
              ]
            }
          ]
        }
      },
      zh: {
        title: "公司简介",
        seo_title: "公司简介 – 黄金会计师事务所",
        seo_description: "秉承着提供卓越会计与咨询服务的愿景，TDK Group Pty Ltd 已发展成为一家备受信赖的精品事务所。",
        content: {
          hero: {
            title: "公司简介",
            lead: "秉承着提供卓越会计与咨询服务的愿景，TDK Group Pty Ltd 已发展成为一家备受信赖的精品事务所，以专业精神、诚信以及以客户为中心的服务理念而闻名。作为注册执业会计师（CPA）、澳大利亚公共会计师协会（IPA）成员以及注册的ASIC代理，我们为每位客户带来了丰富的专业知识和行业认可。凭借多年的经验，我们以帮助企业和个人应对复杂的财务环境而建立了良好的声誉。我们根据客户的独特需求，提供量身定制的解决方案。凭借专业资质和对卓越服务的坚持，我们的每一项服务都体现了深厚的专业技术和对客户成功的全力支持。"
          },
          sections: [
            {
              kind: "intro",
              title: "发展历程",
              body: [
                "TDK Group由注册执业会计师（CPA）兼ASIC代理黄简先生创立，秉持着帮助客户实现财务成功的热情。从最初为本地企业提供服务的小型事务所起步，我们逐步拓展专业领域，如今已为多个行业的客户提供支持，包括专业服务、零售、制造业和房地产。",
                "多年来，我们的团队始终拥抱创新，持续进行专业提升，以应对不断变化的财务环境。这份承诺确保我们提供的服务既具有前瞻性，又以成熟可靠的方法为基础。"
              ]
            },
            {
              kind: "prose",
              title: "我们的服务",
              body: [ "我们提供全面的专业服务，包括：" ],
              bullets: [
                "– 税务服务：个人与企业税务申报、税务规划、BAS/GST申报以及ATO调查协助。",
                "– 会计服务：记账服务、财务报表编制、PAYG和养老金（Superannuation）准备工作。",
                "– 管理咨询：战略建议、风险管理以及业务流程优化。",
                "– 财务规划：量身定制的财富管理与增长策略。",
                "– 审计服务：以风险为导向的审计，确保符合相关法规要求。",
                "– 移民相关会计服务：为商业与技术移民提供财务报表支持和相关协助。"
              ]
            },
            {
              kind: "prose",
              title: "服务行业",
              body: [ "我们自豪地为多个行业的客户提供支持，包括：" ],
              bullets: [
                "– 专业服务（例如医生、律师）",
                "– 批发与零售",
                "– 餐饮与酒店业",
                "– 建筑施工与建筑设计",
                "– 进出口贸易与制造业",
                "– 房地产与物业开发"
              ]
            },
            {
              kind: "prose",
              body: [ "无论客户来自哪个行业，我们都致力于提供高质量的服务，助力客户实现业务目标并在市场中脱颖而出。" ]
            },
            {
              kind: "prose",
              title: "追求卓越",
              body: [
                "在TDK Group，我们以专业和道德标准为驱动力。凭借深厚的行业知识和丰富的经验，我们为客户提供及时、可靠、积极的解决方案，始终确保客户信息的保密性和成功。我们以建立长期合作关系为荣，深知客户的成功就是我们的成功。"
              ]
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
        seo_title: "Our Services – TDK Group Pty Ltd",
        seo_description: "At TDK Group Pty Ltd, we adhere to the highest professional and ethical standards, ensuring excellence in every service we provide.",
        content: {
          hero: {
            title: "Our Services",
            lead: "At TDK Group Pty Ltd, we adhere to the highest professional and ethical standards, ensuring excellence in every service we provide. Our commitment extends beyond compliance; we strive to deliver innovative, tailored solutions that drive long-term growth and success for our clients. From tax, consulting, and auditing services to bespoke tax planning and financial strategies, we help optimize business operations and organizational structures to meet your unique needs and goals."
          },
          sections: [
            {
              kind: "cards",
              title: "Our Services",
              items: [
                { title: "Taxation Services", slug: "our-services/tax-services" },
                { title: "Business Accounting Services", slug: "our-services/business-services" },
                { title: "Management Consulting", slug: "our-services/management-consulting" },
                { title: "Immigration Related Accounting Services", slug: "our-services/immigration-related-accounting-services" }
              ]
            }
          ]
        }
      },
      zh: {
        title: "我们的服务",
        seo_title: "我们的服务 – 黄金会计师事务所",
        seo_description: "在TDK Group Pty Ltd，我们坚持最高的专业和道德标准，确保每项服务都达到卓越水平。",
        content: {
          hero: {
            title: "我们的服务",
            lead: "在TDK Group Pty Ltd，我们坚持最高的专业和道德标准，确保每项服务都达到卓越水平。我们的承诺不仅限于遵守法规，更注重提供创新且量身定制的解决方案，助力客户实现长期增长和成功。"
          },
          sections: [
            {
              kind: "prose",
              body: [
                "从税务、咨询、审计服务到个性化的税务规划和财务策略，我们帮助优化业务运营和组织结构，以满足您的独特需求和目标。"
              ]
            },
            {
              kind: "cards",
              title: "我们的服务",
              items: [
                { title: "税务服务", slug: "our-services/tax-services" },
                { title: "商业会计服务", slug: "our-services/business-services" },
                { title: "管理咨询与财务服务", slug: "our-services/management-consulting" },
                { title: "移民相关会计服务", slug: "our-services/immigration-related-accounting-services" }
              ]
            }
          ]
        }
      }
    },
    {
      slug: "our-services/tax-services",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 40,
      en: {
        title: "Taxation Services",
        seo_title: "Taxation Services – TDK Group Pty Ltd",
        seo_description: "Navigating the ever-changing and complex tax environment requires expertise and strategic planning.",
        content: service_content(
          title: "Taxation Services",
          lead: "Navigating the ever-changing and complex tax environment requires expertise and strategic planning. At TDK Group Pty Ltd, we specialize in helping individuals and businesses effectively utilize tax laws and regulations to maximize value and achieve financial goals. Our comprehensive tax services are designed to provide clarity, compliance, and long-term benefits.",
          list_title: "Our tax services include:",
          bullets: [
            "– Tax planning and consulting, including real estate investment, import & export, overseas investment etc.",
            "– Individual tax returns",
            "– Company, trust, partnership and SMSF (Self-Managed Superannuation Fund) tax return",
            "– BAS and GST Reporting",
            "– Other indirect tax advice (land tax, payroll, stamp duty, payroll etc.)",
            "– Assistance regarding ATO investigations and audits, including capital gains tax, GST and overseas income"
          ],
          cta: "Contact us to get started today"
        )
      },
      zh: {
        title: "税务服务",
        seo_title: "税务服务 – 黄金会计师事务所",
        seo_description: "应对不断变化且复杂的税务环境需要专业知识与战略规划。",
        content: service_content(
          title: "税务服务",
          lead: "应对不断变化且复杂的税务环境需要专业知识与战略规划。在TDK Group Pty Ltd，我们专注于帮助个人和企业有效利用税法和法规，实现价值最大化并达成财务目标。我们的全面税务服务旨在提供清晰的指导、合规性保障及长期效益。",
          list_title: "我们的税务服务包括：",
          bullets: [
            "– 个人所得税申报",
            "– 公司、信托、合伙企业及自管养老金基金（SMSF）的税务申报",
            "– 税务规划与咨询，包括房地产投资、进出口贸易及海外投资等",
            "– BAS和GST申报",
            "– 协助应对ATO调查与审计，包括资本利得税、GST及海外收入相关事宜"
          ],
          cta: "联系我们，讨论适合您的服务方案。",
          label: "联系我们"
        )
      }
    },
    {
      slug: "our-services/business-services",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 41,
      en: {
        title: "Business Accounting Services",
        seo_title: "Business Accounting Services – TDK Group Pty Ltd",
        seo_description: "At TDK Group, we are committed to helping your business achieve operational efficiency and long-term success.",
        content: service_content(
          title: "Business Accounting Services",
          lead: "At TDK Group, we are committed to helping your business achieve operational efficiency and long-term success. By providing high-quality services and proactive support, we ensure your business is well-positioned to grow and thrive in a competitive market.",
          list_title: "Our business services include:",
          bullets: [
            "– Bookkeeping services",
            "– Preparation of financial statements",
            "– Professional and practical accounting training tailored to your team’s needs and consulting",
            "– Preparation of PAYG, Superannuation, and Other Reports",
            "– Trade mark application",
            "– Superannuation and Workcover",
            "– Development and implementation of effective accounting systems (e.g. Xero, MYOB, QuickBooks) customized to your business type for optimal efficiency.",
            "– Business and Entity Registration (Companies, trusts, partnerships, and SMSFs, including ABN, GST, TFN, and PAYG)"
          ],
          cta: "Contact us to get started today"
        )
      },
      zh: {
        title: "商业会计服务",
        seo_title: "商业会计服务 – 黄金会计师事务所",
        seo_description: "在TDK Group，我们致力于帮助您的企业实现运营效率和长期成功。",
        content: service_content(
          title: "商业会计服务",
          lead: "在TDK Group，我们致力于帮助您的企业实现运营效率和长期成功。通过提供高质量的服务和积极的支持，我们确保您的企业在竞争激烈的市场中具备成长与繁荣的优势。",
          list_title: "我们的商业服务包括：",
          bullets: [
            "– 记账服务",
            "– 财务报表编制",
            "– 根据团队需求量身定制的专业会计培训与咨询",
            "– PAYG、养老金（Superannuation）及其他报告的准备",
            "– 为您的企业量身定制并实施高效的会计系统（如MYOB、Excel），以优化运营效率",
            "– 商业与实体注册（公司、信托、合伙企业、自管养老金基金，包括ABN、GST、TFN和PAYG注册）"
          ],
          cta: "联系我们，讨论适合您的服务方案。",
          label: "联系我们"
        )
      }
    },
    {
      slug: "our-services/management-consulting",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 42,
      en: {
        title: "Management Consulting",
        seo_title: "Management Consulting – TDK Group Pty Ltd",
        seo_description: "The right management operational decision determines the direction of the client development.",
        content: service_content(
          title: "Management Consulting",
          lead: "The right management operational decision determines the direction of the client development. At TDK Group, we are committed to providing actionable, forward-thinking solutions that empower businesses to thrive in today’s competitive market. Whether you’re looking to restructure, expand, or improve your operations, our tailored services are designed to help you succeed.",
          list_title: "Our management consulting services include:",
          bullets: [
            "– Individual salary restructuring and business structure planning",
            "– Business process consulting and optimization",
            "– Operational strategy and organizational consulting",
            "– Risk management, business benchmarking and reviews",
            "– Business feasibility assessments and planning (including business in real estate and overseas investment)",
            "– General strategic advice",
            "– Business sale and purchase advisory (including vendor’s statement, Form 2, value and risk assessment)"
          ],
          cta: "Contact us to get started today"
        )
      },
      zh: {
        title: "管理咨询与财务服务",
        seo_title: "管理咨询与财务服务 – 黄金会计师事务所",
        seo_description: "正确的管理和运营决策决定了客户发展的方向。",
        content: service_content(
          title: "管理咨询与财务服务",
          lead: "正确的管理和运营决策决定了客户发展的方向。在TDK Group，我们致力于提供可操作且具有前瞻性的解决方案，助力企业在当今竞争激烈的市场中蓬勃发展。无论您是希望重组、扩展还是优化运营，我们量身定制的服务都旨在助您取得成功。",
          list_title: "我们的管理咨询与财务服务包括：",
          bullets: [
            "– 个人薪资重组与企业架构规划",
            "– 业务流程咨询与优化",
            "– 运营战略与组织管理咨询",
            "– 风险管理",
            "– 商业可行性评估与规划（包括房地产和海外投资领域的业务）",
            "– 综合战略建议",
            "– 企业买卖咨询（包括卖方声明、Form 2、价值与风险评估）"
          ],
          cta: "联系我们，讨论适合您的服务方案。",
          label: "联系我们"
        )
      }
    },
    {
      slug: "our-services/immigration-related-accounting-services",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 43,
      en: {
        title: "Immigration Related Accounting Services",
        seo_title: "Immigration Related Accounting Services – TDK Group Pty Ltd",
        seo_description: "Navigating the financial requirements for immigration applications can be complex and time-consuming.",
        content: {
          hero: {
            title: "Immigration Related Accounting Services",
            lead: "Navigating the financial requirements for immigration applications can be complex and time-consuming. At TDK Group Pty Ltd, we specialize in providing tailored accounting solutions to support individuals and businesses with their migration needs. Our expertise ensures that your financial documentation is accurate, compliant, and aligned with Australian regulatory requirements, giving you confidence throughout the migration process."
          },
          sections: [
            {
              kind: "prose",
              title: "Our immigration-related accounting services include:",
              body: [
                "Business Skilled Migration Visa (188A, 188B, 188C/132):"
              ],
              bullets: [
                "– Preparation of detailed business migration accounts.",
                "– Development of financial reports to demonstrate compliance with visa requirements.",
                "– Comprehensive account audits to validate financial data for submission."
              ]
            },
            {
              kind: "prose",
              body: [
                "Temporary Work (Skilled) Visa 457—-processing of related financial reporting and auditing required by visa application."
              ]
            },
            {
              kind: "cta",
              title: "Contact us to get started",
              body: "Contact us to get started",
              label: "Contact Us",
              slug: "contact-us"
            }
          ]
        }
      },
      zh: {
        title: "移民相关会计服务",
        seo_title: "移民相关会计服务 – 黄金会计师事务所",
        seo_description: "处理移民申请中的财务要求既复杂又耗时。",
        content: {
          hero: {
            title: "移民相关会计服务",
            lead: "处理移民申请中的财务要求既复杂又耗时。在TDK Group Pty Ltd，我们专注于为个人和企业提供量身定制的会计解决方案，支持其移民需求。我们的专业知识确保您的财务文件准确无误，符合澳大利亚的监管要求，让您在移民过程中充满信心。"
          },
          sections: [
            {
              kind: "prose",
              title: "我们的移民相关会计服务包括：",
              body: [ "商业技术移民签证（188, 888）:" ],
              bullets: [
                "– 准备详尽的商业移民财务报表",
                "– 制作财务报告以证明符合签证要求",
                "– 进行全面财务审计，验证提交的数据"
              ]
            },
            {
              kind: "prose",
              title: "临时工作（技术类）签证（457）:",
              bullets: [
                "– 准备签证申请所需的财务报告与审计",
                "– 协助满足移民局制定的财务文件标准"
              ]
            },
            {
              kind: "cta",
              title: "联系我们，讨论适合您的服务方案。",
              body: "联系我们，讨论适合您的服务方案。",
              label: "联系我们",
              slug: "contact-us"
            }
          ]
        }
      }
    },
    {
      slug: "audit-services",
      template: "service",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 44,
      en: {
        title: "Audit Services",
        seo_title: "Audit Services – TDK Group Pty Ltd",
        seo_description: "We offer risk oriented audit service to ensure the information clients provide comply with relevant accounting standards legal obligation.",
        content: {
          hero: {
            title: "Audit Services",
            lead: "We offer risk oriented audit service to ensure the information clients provide comply with relevant accounting standards legal obligation.Our audit services include:"
          },
          sections: [
            {
              kind: "prose",
              title: "Our audit services include:",
              bullets: [
                "Reviewing service;",
                "Audit on accounts and financial report in accordance with Corporation Act 2011;",
                "· Other review and audit services as required by clients."
              ]
            }
          ]
        }
      },
      zh: {
        title: "审计服务",
        seo_title: "审计服务 – 黄金会计师事务所",
        seo_description: "我们提供以风险为导向的审计服务，确保客户提供的信息符合相关会计准则和法定义务的要求。",
        content: {
          hero: {
            title: "审计服务",
            lead: "我们提供以风险为导向的审计服务，确保客户提供的信息符合相关会计准则和法定义务的要求。"
          },
          sections: [
            {
              kind: "prose",
              title: "我们的审计业务服务包括：",
              bullets: [
                "• 审阅服务",
                "• 符合《公司法》要求的会计信息和财务报表审计",
                "• 应客户要求的其他审阅和审计服务"
              ]
            }
          ]
        }
      }
    },
    {
      slug: "our-team",
      template: "standard",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: 80,
      en: {
        title: "Our Team",
        seo_title: "Our Team – TDK Group Pty Ltd",
        seo_description: "Tom Huang is an experienced and highly qualified professional with over 20 years of expertise in accounting.",
        content: {
          hero: {
            title: "Our Team",
            lead: "Tom Huang Director | CPA | SMSF Auditor | Tax Agent | ASIC Agent"
          },
          sections: [
            {
              kind: "profile",
              title: "Tom Huang",
              subtitle: "Director | CPA | SMSF Auditor | Tax Agent | ASIC Agent",
              contact: "tomh@tdkgroup.com.au",
              body: [ "Email: tomh@tdkgroup.com.au" ]
            },
            {
              kind: "prose",
              title: "Professional Qualifications:",
              bullets: [
                "Certified Practicing Accountant (CPA)",
                "IPA Authorised Agent",
                "SMSF Auditor (Self-managed superannuation auditor)",
                "Registered Tax Agent",
                "ASIC Agent"
              ]
            },
            {
              kind: "prose",
              title: "Occupation Background:",
              body: [
                "Tom Huang is an experienced and highly qualified professional with over 20 years of expertise in accounting. As a registered Tax Agent, ASIC Agent, Certified Practicing Accountant (CPA), and SMSF Auditor, Tom brings a wealth of knowledge to his role as Director of TDK Group.",
                "Throughout his career, Tom has held senior positions across multiple industries, which has provided him with a unique, comprehensive understanding of the market. He has also undertaken in-depth studies in public accounting, equipping him with a solid grasp of relevant laws and regulations. This, combined with his dedication to exceptional client service, has helped him maintain long-term, trusted relationships with clients.",
                "Tom’s career is built on a foundation of professional ethics and a commitment to staying at the forefront of accounting practices. He regularly participates in ongoing education and professional development to ensure that he remains up-to-date with the latest industry trends, tax laws, and regulatory changes.",
                "With a decade of experience in public accounting, Tom has worked with clients from a wide range of industries and professions. His services extend beyond basic tax and consulting, encompassing tailored tax planning, organizational structuring, and operational guidance. Tom’s extensive expertise in the construction industry, real estate investment, and overseas investments allows him to offer professional advice at every stage of his clients’ development."
              ]
            }
          ]
        }
      },
      zh: {
        title: "我们的团队",
        seo_title: "我们的团队 – 黄金会计师事务所",
        seo_description: "Tom是一位拥有超过20年会计经验的资深专业人士。",
        content: {
          hero: {
            title: "我们的团队",
            lead: "Tom Huang 董事 | 注册会计师 (CPA) | SMSF 审计师 | 税务代理 | ASIC 代理"
          },
          sections: [
            {
              kind: "profile",
              title: "Tom Huang",
              subtitle: "董事 | 注册会计师 (CPA) | SMSF 审计师 | 税务代理 | ASIC 代理",
              contact: "tomh@tdkgroup.com.au",
              body: [ "邮箱: tomh@tdkgroup.com.au" ]
            },
            {
              kind: "prose",
              title: "专业资质",
              bullets: [
                "注册会计师 (Certified Practicing Accountant, CPA)",
                "IPA 授权代理",
                "SMSF 审计师（自我管理养老金审计师）",
                "注册税务代理 (Registered Tax Agent)",
                "ASIC 代理 (ASIC Agent)"
              ]
            },
            {
              kind: "prose",
              title: "职业背景",
              body: [
                "Tom是一位拥有超过20年会计经验的资深专业人士，持有注册税务代理、ASIC代理、注册会计师 (CPA) 和SMSF审计师资格。他作为TDK Group的董事，凭借其丰富的专业知识和实践经验，为客户提供卓越的服务。",
                "在职业生涯中，Tom曾担任多个行业的高级职务，这使他能够深入理解市场运作，并积累了全面的行业知识。他还深入研究了公共会计领域，具备对相关法律法规的扎实掌握。凭借对卓越客户服务的专注，他与客户建立了长期、值得信赖的合作关系。",
                "Tom的职业生涯建立在专业道德的基础上，并始终致力于站在会计实践的最前沿。他定期参加持续教育和专业发展培训，以确保其紧跟行业最新趋势、税务法律及监管变化。",
                "在公共会计领域拥有十余年经验的Tom，服务范围覆盖多个行业和职业。他不仅提供基础的税务和咨询服务，还提供量身定制的税务规划、组织架构设计和运营指导。他在建筑行业、房地产投资和海外投资领域拥有广泛的专业知识，能够在客户发展的每个阶段提供专业建议。"
              ]
            }
          ]
        }
      }
    },
    {
      slug: "careers",
      template: "standard",
      show_in_nav: false,
      show_in_footer: true,
      sort_order: 90,
      en: {
        title: "Careers",
        seo_title: "Careers – TDK Group Pty Ltd",
        seo_description: "At TDK Group, we believe in empowering businesses and individuals to achieve financial success.",
        content: {
          hero: {
            title: "Careers",
            lead: "At TDK Group, we believe in empowering businesses and individuals to achieve financial success. Our team thrives in a collaborative, innovative, and client-focused environment. If you’re passionate about accounting, consulting, or helping businesses grow, we’d love to hear from you!"
          },
          sections: [
            {
              kind: "prose",
              title: "When you join TDK Group, you’ll enjoy:",
              bullets: [
                "Career Development: Ongoing training and growth opportunities.",
                "Supportive Culture: A team that values collaboration and innovation.",
                "Flexible Work Options: Hybrid work environments tailored to modern needs.",
                "Industry Expertise: Opportunities to work with clients across diverse industries."
              ]
            },
            {
              kind: "prose",
              title: "How to apply",
              body: [
                "Send your resume and cover letter to tomh@tdkgroup.com.au with the subject line [Position Name] Application."
              ]
            },
            {
              kind: "prose",
              title: "Internship opportunities",
              body: [
                "Are you a university student looking for real-world experience in the accounting and consulting industry? At TDK Group, we offer internships designed to equip students with practical skills and insights into the professional world. Our internship applications are open year round so you don’t have to wait until summer or winter breaks to gain hands on experience!"
              ]
            },
            {
              kind: "prose",
              title: "Eligibility:",
              bullets: [
                "– Current university students majoring in Accounting, Finance, Business, or a related field.",
                "– Strong communication and analytical skills.",
                "– A proactive attitude and willingness to learn."
              ]
            },
            {
              kind: "prose",
              body: [
                "*Applicants who are fluent in Mandarin are highly encouraged to apply."
              ]
            },
            {
              kind: "prose",
              title: "How to Apply",
              body: [
                "Send your resume to tomh@tdkgroup.com.au with the subject line [Name] Internship Application."
              ]
            },
            {
              kind: "prose",
              title: "Contact Us",
              body: [
                "If you have any questions about current opportunities or the application process, feel free to reach out to us at tomh@tdkgroup.com.au."
              ]
            }
          ]
        }
      },
      zh: {
        title: "职业机会",
        seo_title: "职业机会 – 黄金会计师事务所",
        seo_description: "在 TDK Group，我们致力于帮助企业和个人实现财务成功。",
        content: {
          hero: {
            title: "职业机会",
            lead: "在 TDK Group，我们致力于帮助企业和个人实现财务成功。我们的团队在一个充满协作、创新和以客户为中心的环境中茁壮成长。如果您热衷于会计、咨询或帮助企业发展，我们期待您的加入！"
          },
          sections: [
            {
              kind: "prose",
              title: "为什么选择我们？加入 TDK Group，您将享受以下优势：",
              bullets: [
                "职业发展：持续的培训与成长机会。",
                "支持性的企业文化：一个注重协作与创新的团队。",
                "灵活的工作选择：结合现代需求的混合工作模式。",
                "行业专业知识：与来自多个行业的客户合作的机会。"
              ]
            },
            {
              kind: "prose",
              title: "如何申请",
              body: [
                "请将您的简历和求职信发送至 tomh@tdkgroup.com.au，邮件主题请注明 [职位名称]申请。"
              ]
            },
            {
              kind: "prose",
              title: "实习机会",
              body: [
                "您是希望在会计与咨询行业获得真实工作经验的大学生吗？在 TDK Group，我们提供专为学生设计的实习机会，帮助您掌握实践技能并深入了解职业世界。我们的实习申请全年开放，因此您无需等待暑假或寒假就可以获得实操经验！"
              ]
            },
            {
              kind: "prose",
              title: "申请资格：",
              bullets: [
                "– 目前就读于会计、金融、商业或相关专业的大学生。",
                "– 具备较强的沟通能力和分析能力。",
                "– 积极主动，乐于学习。"
              ]
            },
            {
              kind: "prose",
              title: "如何申请",
              body: [
                "请将您的简历发送至 tomh@tdkgroup.com.au，邮件主题请注明 [姓名] 实习申请。"
              ]
            },
            {
              kind: "prose",
              title: "联系我们",
              body: [
                "如果您对当前职位或申请流程有任何疑问，请随时通过 tomh@tdkgroup.com.au 与我们联系。"
              ]
            }
          ]
        }
      }
    },
    {
      slug: "contact-us",
      template: "contact",
      show_in_nav: true,
      show_in_footer: true,
      sort_order: 100,
      en: {
        title: "Contact Us",
        seo_title: "Contact Us – TDK Group Pty Ltd",
        seo_description: "We’re here to help! Reach out to us using the details below and our team will get back to you promptly.",
        content: {
          hero: {
            title: "Contact Us",
            lead: "We’re here to help! Reach out to us using the details below and our team will get back to you promptly."
          },
          sections: [
            {
              kind: "contact",
              title: "Contact Us",
              details: [
                { label: "Phone", value: "03 9890 4988" },
                { label: "Email", value: "info@tdkgroup.com.au" },
                { label: "Office Address", value: "1/550 Whitehorse Rd, Surrey Hills, VIC 3127" },
                { label: "Business Hours", value: "Monday to Friday, 9:30 AM – 6:00 PM" }
              ]
            },
            {
              kind: "prose",
              body: [
                "For inquiries or to schedule a consultation contact us at 03 9890 4988 or submit a contact form below"
              ]
            }
          ]
        }
      },
      zh: {
        title: "联系我们",
        seo_title: "联系我们 – 黄金会计师事务所",
        seo_description: "我们随时为您提供帮助！请通过以下联系方式与我们取得联系，我们的团队将及时回复您的需求。",
        content: {
          hero: {
            title: "联系我们",
            lead: "我们随时为您提供帮助！请通过以下联系方式与我们取得联系，我们的团队将及时回复您的需求。"
          },
          sections: [
            {
              kind: "contact",
              title: "联系我们",
              details: [
                { label: "电话", value: "03 9890 4988" },
                { label: "手机", value: "0426 969 868" },
                { label: "邮箱", value: "info@tdkgroup.com.au" },
                { label: "办公地址", value: "1/550 Whitehorse Rd, Surrey Hills, VIC 3127" },
                { label: "办公时间", value: "周一至周五 9:30 – 18:00\n周六、周日请提前预约" }
              ]
            },
            {
              kind: "prose",
              body: [
                "如需咨询或预约，请致电03 9890 4988，或通过下方表单与我们联系。"
              ]
            }
          ]
        }
      }
    }
  ].freeze

  def self.pages
    PAGES.map(&:deep_dup)
  end

  def self.known_slugs
    PAGES.map { |page| page.fetch(:slug) }
  end
end
