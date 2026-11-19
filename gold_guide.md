
Your legacy worksheets have been moved to your personal workspace ("My Workspace").
Show me now
Workspaces
Databases
1021 Creative x Snowflake - The GOLD Layer, in Plain English
For Victor and the 1021 team. Database: POC_1021_GOLD. Refreshed every morning, automatically.

1. The one-minute version
Every morning Snowflake pulls two things:

Tubular: what's trending on video. The top 400 videos and top 100 channels per platform, on YouTube, TikTok, Instagram, Facebook and Twitch.
Meltwater: what people are saying about our four themes, Gaming, Fashion, Anime & Manga and Sports, across X, Reddit, news, Bluesky and more.
Gold turns all of that into one table per dashboard. Each table is clean, labeled and ready for BI tools or for asking questions in plain English (Cortex Analyst).

It also does three things neither tool does on its own:

Separates culture from advertising. The top of every global leaderboard is full of paid brand ads. Gold flags them so dashboards show what culture is actually responding to.
Gives every video a theme. Tubular's trending lists aren't filtered by topic, so gold tags videos as Gaming, Fashion, Anime or Sports using Tubular's own labels.
Connects the two sources through hashtags. "#pfw was the #2 hashtag in the Fashion conversation and on 9 trending Instagram videos that gained 339M views." A signal that's strong in both places is the "spot it before it peaks" moment.
2. How it's organized
BRONZE   raw API responses, exactly as received          (never changed - full history)
SILVER   cleaned, one table per thing the APIs return    (videos, creators, mentions, posts...)
GOLD     ready for business:
  CORE        shared building blocks - dates, platforms, countries, languages,
              themes, the video and creator directories, the hashtag bridge
  REPORTING   one table per dashboard  <-- start here
3. The dashboard tables (POC_1021_GOLD.REPORTING)
Dashboard	Table	One row is...	Answers questions like
Trending videos	RPT_TRENDING_VIDEOS	a video's spot on a platform's leaderboard on a day	"Top 10 TikToks this week, no ads." "French Gaming videos trending on YouTube." "Which videos are new on the list today?"
Trending channels	RPT_TRENDING_CHANNELS	a creator's spot on a platform's fastest-growing list on a day	"Fastest-growing Mid-tier creators in Korea." "Channels under 1 year old gaining the most followers."
Trending audio	RPT_TRENDING_AUDIO	a sound used by trending videos on a day	"Which sounds are on the most trending TikToks?" (with example videos)
Channel search	RPT_CREATOR_PROFILES	a creator's account on one platform	"Gaming creators in Brazil with 100K-500K followers." "Whose audience is mostly 18-24 and female?"
Creator growth	RPT_CREATOR_ACTIVITY_DAILY	a creator's gains on one platform on one day	"Chart this creator's daily views and follower growth."
Conversation overview	RPT_THEME_CONVERSATION_DAILY	a theme on a day	"How big was the Gaming conversation yesterday vs a normal day? How did it feel?"
Conversation breakdowns	RPT_THEME_CONVERSATION_MIX	a theme x day x sentiment / language / platform	"What share of Anime chatter is Japanese? Positive?"
Trending posts	RPT_TRENDING_POSTS	a post in a theme	"Most-engaged Fashion posts yesterday, with links."
Trending accounts	RPT_TRENDING_ACCOUNTS	an account in a theme's top 50 on a day	"Who's driving the Sports conversation this week?"
Trending hashtags	RPT_TRENDING_HASHTAGS	a hashtag in a theme on a day, both sources side by side	"Which hashtags are big in the conversation and on trending video?"
Victor's saved searches	RPT_VICTOR_SAVED_SEARCHES	a result row of one of Victor's Tubular saved searches	Victor's own queries, run on a schedule, with ~13 weeks of history
Is the data fresh?	RPT_DATA_FRESHNESS	a gold table	"Is everything up to date this morning?"
4. Five things to know before reading the numbers
1) There are two kinds of tables: snapshots and time series
Snapshots (the leaderboards): trending videos, channels and audio. Each morning we photograph today's top lists. Pick one day; never add rows up across days, because the same video appears every day it's trending. "Trending this week" means the latest day, or DAYS_ON_LEADERBOARD.
Time series (true daily totals): conversation, creator growth, hashtag mentions. You can add these up across days ("mentions in the last 7 days").
Every column description in Snowflake says which kind it is.

2) Dates line up on REPORT_DATE
All days are UTC.

Tubular's 06:30 UTC snapshot on Oct 14 measures a window that ended on Oct 13, so its REPORT_DATE is Oct 13.
Meltwater's mentions for Oct 13 also have REPORT_DATE / ACTIVITY_DATE Oct 13.
So both sources sit on the same row of a chart.

3) The "culture lens" is the default, and it matters
On the raw leaderboards, about a quarter of the top 10 are paid ads, for example a YouTube pads ad with 143M views and 11 engagements. Gold flags every video:

Flag	Meaning
IS_BRANDED	Known brand or paid content. Any of: the publisher is a brand, media company or aggregator; the video has a disclosure hashtag (#ad, #...partner, #publicidad); Tubular files it under Advertising; or the title has a promo phrase ("buy here", "flash sale", "TikTok Shop"). BRANDED_REASON says which.
IS_LOW_ENGAGEMENT	5M+ views but under 1 engagement per 1,000 views: huge reach that nobody reacted to. That's the signature of paid placement.
IS_CULTURE_SIGNAL	Neither of the above. Use this, together with CULTURE_RANK, for a clean ranking.
Tubular's original RANK is always kept. Some ads carry no detectable signal, so read the flag as "known branded".

4) Themes on videos are inferred, and that's labeled
Meltwater is themed by design: each theme is a saved search. Tubular's trending lists aren't. Gold tags a video to a theme when Tubular's own labels match, for example:

category Video Games/Minecraft, or
topic "Paris Fashion Week", or
creator genre "Sports", or
hashtag #anime.
BRIDGE_VIDEO_THEME records why each video matched. MATCH_STRENGTH = strong means Tubular itself classified it (category or genre); weak means a topic or hashtag matched. Most trending videos are general entertainment and get no theme. That's expected.

5) Each source keeps its own numbers
Views (Tubular), mentions (Meltwater) and trending-video counts aren't the same unit, so gold never adds them together. They sit side by side, and "rising" is always measured against that source's own past.

5. The cross-source story: hashtags
Hashtags are the one thing both sources truly share. A real example from the first day:

Theme	Hashtag	Meltwater: mentions (rank)	Tubular: trending videos	Views gained
Fashion	#pfw	18,486 (#2)	9	339M
Fashion	#diorsummer27	9,815 (#6)	10	373M
Sports	#nfl	21,633 (#19)	4	163M
Anime & Manga	#cosplay	2,802 (#41)	4	86M
RPT_TRENDING_HASHTAGS labels every tag as Conversation + trending video, Conversation only, or Trending video only.
AGG_TERM_MOMENTUM_WEEKLY (in CORE) flags IS_RISING_IN_BOTH: a tag up 25%+ week over week in the conversation and on trending video, above minimum volumes. Until there are two full weeks of history, rows are marked IS_EARLY_READ.
6. What 1021 can change without code
These are simple CSV lists inside the project (dbt_1021/seeds/gold/). Edit one, rebuild, and gold updates.

List	What it controls
gold_themes.csv	The themes and which Meltwater saved search each one uses
gold_theme_rules.csv	How Tubular videos get tagged to themes (categories, topics, genres, hashtags)
gold_branded_hashtags.csv, gold_branded_keywords.csv	What counts as branded or ad content
gold_generic_hashtags.csv	Tags with no topic (#fyp, #viral), flagged so they can be hidden
gold_victor_saved_searches.csv	Names and descriptions of Victor's saved searches
ref_size_tiers.csv	Nano / Micro / Mid-tier / Macro / Mega follower cut-offs
THEME_RULE_SUGGESTIONS (in CORE) does part of the work for you. It lists hashtags that are big in a theme's Meltwater conversation, appear on Tubular trending videos, but aren't a theme rule yet. Review it, and paste the good rows into gold_theme_rules.csv.

7. Honest limits (and why)
Limit	Why	What we do about it
Leaderboard history starts Oct 14 and can't be backfilled	Tubular only exposes today's trending lists	History grows daily. Victor's weekly saved searches already go back to July.
Week-over-week trends are "early reads" until about Oct 28; 4-week baselines until about Nov 11	A comparison needs prior weeks	Flagged in the data (IS_EARLY_READ)
Tubular shows the top 400 videos / 100 channels per platform, not everything	API cost (quota)	Pagination is built in. Raising MAX_PAGES in config fetches more.
Country = creator's country	Tubular has no per-video country	Agreed stand-in
X posts have no text, link or handle in Meltwater exports, and Reddit has no text	Meltwater licensing	Links rebuilt from the post id; IS_TEXT_REDACTED flag
Posts are a sample (up to 2,000 per theme per day)	Export limits	Use posts for examples, and the conversation tables for totals
Meltwater accounts have reach, not followers; platform is often unknown	What Meltwater returns	Size tiers apply to Tubular creators only
Audience demographics: top 200 creators, YouTube / Facebook / Instagram, weekly	Tubular cost and platform support	Can be expanded for more quota
Meltwater's latest day can be ~0.5% low	Mentions are indexed late	Each run re-pulls the prior day automatically
Daily YouTube follower gains are rounded	YouTube rounds subscriber counts	Use 7-day / 30-day gains
The channels leaderboard returns a creator's total followers across platforms	That's what the low-cost channel pull returns	TOTAL_... vs PLATFORM_... columns say which is which
8. Try it: example questions
-- Top 10 culture videos on TikTok this week
select culture_rank, title, creator_name, country_name, views_gain, video_url
from POC_1021_GOLD.REPORTING.RPT_TRENDING_VIDEOS
where platform = 'tiktok' and gain_window = '7d' and is_culture_signal
  and snapshot_date = (select max(snapshot_date) from POC_1021_GOLD.REPORTING.RPT_TRENDING_VIDEOS)
order by culture_rank limit 10;

-- Fastest-growing non-brand channels in South Korea
select platform, creator_name, size_tier, total_followers, total_followers_gain_30d, platform_followers, platform_account_url
from POC_1021_GOLD.REPORTING.RPT_TRENDING_CHANNELS
where country_code = 'KR' and not is_branded
  and snapshot_date = (select max(snapshot_date) from POC_1021_GOLD.REPORTING.RPT_TRENDING_CHANNELS)
order by total_followers_gain_30d desc;

-- Hashtags big in the conversation AND on trending video, per theme
select theme_name, hashtag_label, meltwater_mentions, tubular_videos_global, tubular_views_gain_global
from POC_1021_GOLD.REPORTING.RPT_TRENDING_HASHTAGS
where signal_type = 'Conversation + trending video' and not is_generic_tag
order by report_date desc, meltwater_mentions desc;

-- How did each theme's conversation feel yesterday?
select theme_name, mentions, mentions_vs_7d_avg, pct_positive, pct_negative, top_hashtag
from POC_1021_GOLD.REPORTING.RPT_THEME_CONVERSATION_DAILY
where activity_date = current_date() - 1;
9. Behind the scenes (one paragraph)
Schedule: Meltwater runs at 06:00 UTC and Tubular at 06:30 UTC (plus a weekly Tubular run on Mondays).
Pipeline: each run lands raw data in BRONZE, then dbt rebuilds SILVER and every GOLD table downstream.
Tests: every gold table has automated checks (no duplicate rows, valid codes, joins that resolve). A failed check stops bad data before it reaches a dashboard.
Docs: every table and column description in this guide also appears as a comment in Snowflake.
Code: everything is in the shared workspace POC_1021_SILVER.PUBLIC.POC_1021_PIPELINE.
10. Saved searches: live, niche topics (POC_1021_GOLD.SEARCH)
The trending tables above show what's big globally. Saved searches answer the niche questions, like "the practice of witchcraft globally" or "creators who use puppets". They pull live from Tubular and Meltwater, only when someone asks.

How it works

Build a search on New / edit search in Beehive. You can type a sentence and let Cortex draft the keywords, translations, hashtags and exclusions. You can also fill in the form yourself. Every search goes into a team library that everyone can see.
Run it. One click calls Tubular and Meltwater. It returns the top 200 videos and top 50 creators, plus the full daily conversation volume, sentiment, countries, top hashtags and top authors. A run takes about 20-30 seconds.
Cortex checks relevance. It decides whether each video and creator is really about the topic, for example a ventriloquist rather than a "puppet government". Dashboards show on-topic results by default.
The dashboards fill in instantly. These are Video search, Creator search and Trends, plus an Ask Cortex panel on each one. Running a search doesn't need a dbt run: the SEARCH tables are dbt views over the raw responses, so new results show up the moment they land.
The tables

View	One row per	Use it for
SEARCH_CATALOG	saved search	The library: keywords, owner, last run, headline numbers, momentum
SEARCH_VIDEO_RESULTS	search x video	Top videos (V7 / E7, format, country, branded, on-topic, new since last run)
SEARCH_CREATOR_RESULTS	search x creator	Creators: size, 30-day growth, channel age, audience (once fetched), on-topic
SEARCH_CONVERSATION_DAILY	search x day x series	Momentum over time. mentions is Meltwater's true daily volume.
SEARCH_CONVERSATION_MIX	search x sentiment / country / language	Who is talking, and how they feel
SEARCH_TOP_TERMS	search x hashtag / author	What the conversation and the videos are made of
SEARCH_MOMENTUM	search	Last 7 days vs the 7 before: Rising / Steady / Cooling, plus the peak day
SEARCH_RUN_DIFF	search	What's new or dropped since the previous run
Read before using

Videos and creators are the top N Tubular ranked, not every match. The total match count is in SEARCH_CATALOG.TUBULAR_VIDEO_MATCHES. Mentions are true totals.
Tubular can't filter creators by follower count, channel age or audience age. Those filters run in Snowflake, on the creators Tubular returns.
Audience demographics and a 30-day daily trend for a creator are fetched when someone opens that creator, then cached for 7 days. Tubular has demographics for YouTube, Facebook and Instagram only.
Keyword search is noisy. Use exclusions to drop the wrong meanings ("sock puppet", "puppet regime"). Cortex suggests them when it drafts a search.
Cost and guard rails

A default run costs about 1,450 Tubular units (Tubular gives about 500K a month) and 3 of Meltwater's 50 daily calls.
Optional "Tubular daily totals" give true daily uploads and views for every matching video. They add about 3,100 units per 30 days.
The guard rails live in the run procedure, so they apply to the app, to SQL and to the agent alike. A run is refused when:
a person would go over 15K units in a day, or
the monthly Tubular balance would fall below 100K, which protects the daily pipeline.
The conversation pull is skipped when fewer than 8 Meltwater calls are left that day.
Edit the limits in POC_1021_BRONZE.SEARCH.SEARCH_SETTINGS.
Ask Cortex / Snowflake CoWork

The Beehive Search agent (POC_1021_GOLD.SEARCH.BEEHIVE_SEARCH_AGENT) answers questions over the semantic view SV_SEARCH. Try:

"What's driving the Witchcraft conversation this week?"
"Which puppet creators are growing fastest?"
"Compare momentum across my searches"
The agent can also draft, estimate, save and run searches. It shows you the cost and waits for your "yes" before it runs anything. It appears automatically in Snowflake CoWork (ai.snowflake.com) for the POC_1021_ANALYST role. It is the same agent behind the Ask Cortex panels in Beehive.

-- Top on-topic Witchcraft videos this week
select title, platform_name, creator_name, views_7d, video_url
from POC_1021_GOLD.SEARCH.SEARCH_VIDEO_RESULTS v
join POC_1021_GOLD.SEARCH.SEARCH_CATALOG c using (search_id)
where c.search_name = 'Witchcraft' and coalesce(v.ai_is_relevant, true)
order by views_7d desc nulls last limit 10;

-- Which saved topics are heating up?
select c.search_name, m.momentum, m.mentions_7d, m.mentions_prev_7d, m.mentions_change_pct, m.peak_day
from POC_1021_GOLD.SEARCH.SEARCH_MOMENTUM m join POC_1021_GOLD.SEARCH.SEARCH_CATALOG c using (search_id)
order by m.mentions_change_pct desc;
Behind the scenes

Procedures: search definitions, runs and raw responses live in POC_1021_BRONZE.SEARCH. The procedures are SP_DRAFT_SEARCH, SP_SAVE_SEARCH, SP_RUN_SEARCH, SP_SCORE_RELEVANCE and SP_CREATOR_DETAIL.
One compiler: a single module, search_compiler.py, turns a search into Tubular and Meltwater requests. The app, the procedures and the agent all use it.
No leakage: search results stay separate from the daily pipeline, so niche searches never change the trending tables.
Files: setup scripts 09_search.sql, 10_search_ai.sql and 11_search_agent.sql, plus the dbt models in models/gold/search/.
