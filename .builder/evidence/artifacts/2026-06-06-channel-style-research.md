# Channel Style Research

Date: 2026-06-06

Scope: remaining PagePilot distribution channels after removing private-network drafts, short-video drafts, short generic China-platform copy, and one question-answer channel.

## Existing Agent Skills Found

- `launch-strategy` on MCP.Directory: useful as a general product launch strategy skill, not platform-specific enough for PagePilot channel copy. Source: https://mcp.directory/skills/launch-strategy
- `wechat-article-writer` on MCP.Directory: useful signal for WeChat article structure, but it is not installed locally and should not replace our own distribution skill. Source: https://mcp.directory/skills/details/1290/wechat-article-writer
- No strong ready-made skills found for Xiaohongshu, Jike, Shaoshupai, V2EX, Product Hunt, X/Threads, LinkedIn, Reddit, or HN that are better than updating our `launch-distribution-kit` platform map.

## Platform Style Notes

### 即刻

Source signals:

- App Store listing positions Jike as a niche-circle and daily-life sharing community. Source: https://apps.apple.com/cn/app/%E5%8D%B3%E5%88%BBapp/id966129812

Write like:

- maker note
- conversational
- honest about what was built and why
- ask for specific feedback

Avoid:

- polished ad copy
- broad claims
- excessive hashtags

### 小红书

Source signals:

- Creator platform exists for posting, data analysis, and commercial creator operations. Source: https://creator.xiaohongshu.com/
- Public rule summaries emphasize authenticity, commercial disclosure, avoiding copied style, and AI-content disclosure where relevant. Source: https://www.zhanghaobang.cn/policy/xiaohongshu-content-policy-2026
- Xiaohongshu is commonly described as informal, social, and "种草笔记" oriented. Source: https://zh.wikipedia.org/wiki/%E5%B0%8F%E7%BA%A2%E4%B9%A6

Write like:

- first-person scenario note
- concrete daily workflow
- title hooks around pain and scene
- screenshot captions and hashtag set

Avoid:

- fake experience
- hard-sell tone
- unsupported claims
- copied influencer style

### 微信公众号

Source signals:

- WeChat has publicly moved against exaggerated/official-sounding clickbait titles and mismatch between title and body. Source: https://www.thepaper.cn/newsDetail_forward_26514412
- WeChat article-writing skills in public skill directories emphasize title, hook, problem scene, structured body, and avoiding title bait. Source: https://mcp.directory/skills/details/1290/wechat-article-writer

Write like:

- founder/product essay
- clear title matching the body
- problem scene first
- structured sections
- one concrete CTA

Avoid:

- "重磅/紧急/官方通知" style titles
- mismatch between title and article
- generic marketing intro

### 头条号 / 今日头条

Source signals:

- Toutiao has posted governance notices against sensational covers/titles and low-quality content that harms user information access. Source: https://www.toutiao.com/article/7506805798228509219/
- Historical summaries report platform action against title bait. Source: https://www.newrank.cn/article/detail/8444

Write like:

- practical utility article
- clear direct headline
- broad-reader explanation
- short paragraphs and visible benefit

Avoid:

- clickbait cover/title
- sensational wording
- vague "神器" claims without explanation

### 少数派

Source signals:

- Shaoshupai/Matrix writing access and article selection are tied to article quality, reads, and likes in public call-for-writing posts. Source: https://sspai.com/post/39703

Write like:

- workflow narrative
- polished but practical
- explain setup, limitation, and actual experience
- include screenshots

Avoid:

- only launch announcement
- shallow feature list
- no workflow context

### V2EX

Source signals:

- V2EX is topic-node based and strongly community-oriented. Source: https://www.v2ex.com/

Write like:

- humble indie share
- direct context
- technical/product details
- ask for feedback

Avoid:

- sales tone
- repeated posting
- inflated claims

### Product Hunt

Source signals:

- Product Hunt launch guide highlights a strong product page, clear gallery, maker engagement, and launch-day replies. Source: https://help.producthunt.com/en/articles/11082221-how-to-launch-on-product-hunt
- Product Hunt post structure includes tagline, description, media gallery, and maker comment. Source: https://help.producthunt.com/en/articles/4849772-posting-on-product-hunt

Write like:

- crisp category and benefit
- upbeat but evidence-backed
- maker comment explains why it exists

Avoid:

- vague tagline
- no screenshots
- disappearing after launch

### Hacker News

Source signals:

- HN guidelines ask users to avoid flamebait, generic promotion, and titles that editorialize. Source: https://news.ycombinator.com/newsguidelines.html
- Show HN guidance is for things people can try and asks titles to begin with "Show HN:". Source: https://news.ycombinator.com/showhn.html

Write like:

- "Show HN: ..." only when there is something public and tryable
- implementation/problem first
- direct and non-hype

Avoid:

- launch-hype wording
- generic marketing copy
- title bait

### Reddit

Source signals:

- Reddit's content policy and spam guidance emphasize authentic participation and avoiding manipulative/spammy behavior. Sources: https://redditinc.com/policies/content-policy and https://support.reddithelp.com/hc/en-us/articles/360043504051-What-constitutes-spam

Write like:

- subreddit-native
- disclose affiliation
- ask for feedback
- adapt to each community

Avoid:

- cross-posting identical promo
- link-only posts
- ignoring subreddit rules

### X / Threads

Source signals:

- X help center focuses on posts, reposts, replies, and threads as native units. Source: https://help.x.com/en/using-x/how-to-post

Write like:

- one sharp idea per post
- short launch post plus thread
- include clear product category near the name

Avoid:

- too many claims in one post
- unexplained product name

### LinkedIn

Source signals:

- LinkedIn Help explains posting formats and professional sharing mechanics. Source: https://www.linkedin.com/help/linkedin/answer/a522433

Write like:

- professional workflow story
- business or creator lesson
- product as example, not only pitch

Avoid:

- casual thread tone
- no professional relevance

### Email / Newsletter

Source signals:

- Mailchimp launch email guidance emphasizes clear subject, direct value, and a focused CTA. Source: https://mailchimp.com/resources/product-launch-email/

Write like:

- clear subject and preview text
- short reason why now
- one primary CTA

Avoid:

- multiple asks
- vague announcement without user value

## Recommendation

Update `launch-distribution-kit/references/platform-map.md` with these platform-specific style rules, especially for:

- WeChat official account
- Toutiao
- Xiaohongshu
- Shaoshupai
- V2EX
- Product Hunt
- HN/Reddit

Then revise PagePilot's distribution pack channel by channel instead of using one generic launch style.
