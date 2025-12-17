# Buds Agent Integration: Cannabis Knowledge Assistant

**Last Updated:** December 16, 2025
**Version:** v0.1
**Vision:** Personal cannabis insights + educational knowledge assistant

---

## Overview

Buds Agent is a **helpful cannabis knowledge assistant** grounded in your personal logs + cited sources, combining:
1. **Universal cannabis knowledge**: Growing, strains, terpenes, consumption methods, brands
2. **Personal memory analysis**: Your logged experiences + patterns
3. **Circle insights**: Aggregated experiences from your trusted friends (opt-in)
4. **Dispensary intelligence**: Product performance, customer preferences, market trends

**Powered by:** DeepSeek/Qwen/Kimi K2 with custom cannabis knowledge base

---

## Agent Capabilities

### Core Knowledge Domains

| Domain | Coverage | Examples |
|--------|----------|----------|
| **Strains** | 2,000+ strains | Blue Dream, Gelato, Sour Diesel profiles |
| **Terpenes** | All major + minor | Myrcene, Limonene, Caryophyllene effects |
| **Effects** | Physical + mental | Relaxation, creativity, pain relief |
| **Consumption methods** | 10+ methods | Joint, bong, vape, edible, tincture |
| **Growing** | Cultivation basics | Soil vs hydro, nutrients, harvest timing |
| **Brands** | Major brands | Cookies, STIIIZY, Jungle Boys, Raw Garden |
| **Dispensaries** | Chains + local | MedMen, Cookies stores, local favorites |
| **Legal/Safety** | Harm reduction | Dosing, interactions, responsible use |

---

## Query Types & Examples

### 1. Personal Memory Analysis

**Query:** *"What strains made me anxious?"*

**Agent response:**
```
Based on your 47 logged sessions, you experienced anxiety with:

1. **Sour Diesel** (3/3 sessions)
   - High THC (26-28%)
   - Sativa-dominant
   - Effect pattern: energized → anxious → paranoid

2. **Super Lemon Haze** (2/2 sessions)
   - Also sativa-dominant, high limonene
   - You noted: "Too intense for evenings"

Recommendation: Stick to hybrids or indicas under 22% THC,
especially those high in CBD (>1%) or linalool (calming terpene).

📊 Citations: [Sessions: Dec 3, Nov 12, Oct 28]
```

---

**Query:** *"Best strain for creative work?"*

**Agent response:**
```
Your top strains for creativity (5-star ratings + "creative" tag):

1. **Blue Dream** (6 sessions, avg 4.8★)
   - You consistently reported: "focused", "creative", "motivated"
   - Best time: Morning/afternoon
   - Method: Vape or joint (not edibles)

2. **Gelato** (4 sessions, avg 4.5★)
   - Balanced hybrid, good for flow state
   - You noted: "Great for writing, not too heavy"

3. **Jack Herer** (3 sessions, avg 4.7★)
   - Sativa-leaning, uplifting
   - "Clear-headed creativity"

Try these next: **Durban Poison** or **Green Crack** (similar terpene
profiles to your favorites, high limonene + pinene).

📊 Citations: [Sessions from last 90 days]
```

---

### 2. Strain & Terpene Education

**Query:** *"What's the difference between myrcene and limonene?"*

**Agent response:**
```
**Myrcene** (earthy, musky aroma)
- Most common terpene in cannabis
- Effects: Sedating, muscle-relaxing, "couch-lock"
- Found in: Indicas, mangoes, lemongrass
- Strains high in myrcene: Granddaddy Purple, OG Kush

**Limonene** (citrus aroma)
- Second most common
- Effects: Uplifting, mood-boosting, energizing
- Found in: Sativas, citrus fruits
- Strains high in limonene: Super Lemon Haze, Durban Poison

🧪 Fun fact: Eating a mango 30 min before smoking can enhance
myrcene's effects (increases THC absorption).

Your preferences: Based on your logs, you rate strains with high
limonene 4.2★ on average vs 3.1★ for high myrcene strains.
You're a limonene person!
```

---

**Query:** *"Tell me about the entourage effect"*

**Agent response:**
```
The **entourage effect** is the synergy between cannabinoids (THC, CBD, etc.)
and terpenes. Together, they produce effects greater than THC alone.

Example:
- **THC alone**: Euphoria, but can cause anxiety in some people
- **THC + CBD**: Reduces anxiety, smoother high
- **THC + linalool (terpene)**: Extra calming, anti-anxiety
- **THC + pinene + limonene**: Alertness + focus

This is why two strains with 25% THC can feel completely different—
it's the terpene profile that matters.

🔬 Your data supports this: Your highest-rated sessions (4.5★+) had
balanced cannabinoid ratios (THC 18-24%, CBD 0.5-2%) with diverse
terpene profiles. Your 3★ sessions were often "THC bombs" (30%+ THC,
low terpenes).

Takeaway: Don't chase THC%. Look for quality, well-cured flower with
rich terpene profiles.
```

---

### 3. Consumption Method Guidance

**Query:** *"Should I smoke or vape?"*

**Agent response:**
```
Here's how they compare based on your 73 logged sessions:

**Smoking (joint/bong)**
Pros:
- Full entourage effect (all cannabinoids + terpenes)
- Immediate effects (2-5 min onset)
- Social/ritual aspect
- You rated: 4.3★ avg

Cons:
- Harsh on lungs (you noted "coughing" in 8 sessions)
- Burns off some terpenes (high heat)

**Vaping (dry herb)**
Pros:
- Smoother (you noted "cleaner high" in 12 sessions)
- Temperature control (preserve terpenes)
- Less odor
- You rated: 4.5★ avg

Cons:
- Device maintenance
- Battery life

Your pattern: You prefer vaping for daytime/creative work (higher ratings),
smoking for social sessions with friends.

Recommendation: **Vape for solo, smoke for social.**

Alternative: Try a **dry herb vape** at 365-385°F for flavor + effects
without harshness.
```

---

### 4. Dispensary Recommendations

**Query:** *"Where should I buy Blue Dream in SF?"*

**Agent response:**
```
Top dispensaries for Blue Dream in San Francisco (based on
your preferences + Circle intel):

1. **Cookies SF** (Haight St)
   - Current price: $45/8th
   - THC: 23.5%, CBD: 0.8%
   - Your friend Alice bought this batch (rated 5★)
   - In stock as of 2 hours ago

2. **SPARC** (Mission)
   - Current price: $40/8th
   - THC: 22.1%, CBD: 1.2%
   - Higher CBD (you prefer this ratio)
   - Known for quality curing

3. **Barbary Coast** (FiDi)
   - Premium selection ($50-60/8th)
   - You rated their products 4.7★ avg
   - Great for special occasions

💡 Pro tip: SPARC has 15% off first-time customers. Mention you're new.

🗺️ Map: [Shows 3 locations, you're 0.3mi from Cookies]
```

---

### 5. Growing & Cultivation (Educational, Jurisdiction-Dependent)

**Query:** *"How do I grow indicas indoors?"*

**Agent response:**
```
**Note:** Cannabis cultivation is illegal in many jurisdictions. This information is for educational purposes only in areas where home cultivation is legal. Check your local laws before proceeding.

**Indoor Cannabis Cultivation Basics (General Education):**

**Why some prefer indicas for indoor growing:**
- Generally shorter, bushier plants (easier height management)
- Typically 7-9 week flower period
- Often suited for small spaces

**General considerations for indoor cultivation:**
- Lighting requirements and schedules
- Environmental controls (temp, humidity)
- Growth medium selection
- Ventilation and odor management

**Legal compliance reminders:**
- Verify home cultivation is legal in your jurisdiction
- Understand plant count limits where applicable
- Comply with local regulations re: security, minors, etc.

**For detailed cultivation guidance:** Consult licensed resources in your area. Laws vary widely; stay informed and compliant.

⚠️ Buds does NOT provide actionable cultivation instructions. This is high-level educational context only.
```

---

### 6. Harm Reduction & Safety

**Query:** *"Can I mix weed and alcohol?"*

**Agent response:**
```
**General harm reduction information:**

Mixing cannabis and alcohol can amplify impairment. General considerations:
- Combined substances increase impairment unpredictably
- May increase risk of adverse effects (nausea, dizziness, impaired judgment)
- Order of consumption may affect experience

**Harm reduction principles:**
1. **Safest approach:** Avoid mixing substances
2. **If mixing:** Start with minimal amounts of each
3. **Stay hydrated** and have a safe environment
4. **NEVER drive** or operate machinery after consuming either substance, especially both

**Your logged experiences:**
You have logged mixing cannabis and alcohol:
- Sept 15: "Too dizzy, regretted it" (2★)
- Oct 3: "One glass wine + vape was fine" (4★)

Based on your personal history, lower quantities appeared more manageable for you. Everyone responds differently.

⚠️ **Critical safety:** NEVER drive after consuming cannabis, alcohol, or both. Effects are unpredictable and dangerous. Impaired driving is illegal and life-threatening.

📋 **Not medical advice:** This is educational harm reduction information only. Consult a healthcare professional for personalized guidance.
```

---

## Agent Architecture

### System Design

```
User Query → Query Parser → Knowledge Router → Response Generator
                                    ↓
                    ┌───────────────┼───────────────┐
                    ↓               ↓               ↓
            Personal Memory    Cannabis KB    Circle Insights
            (Local GRDB)       (Claude)       (Aggregated)
```

### Knowledge Router Logic

```swift
func routeQuery(_ query: String) -> QueryPlan {
    let intent = classifyIntent(query)

    switch intent {
    case .personalMemory:
        // "What strains did I like?"
        return .init(
            sources: [.localReceipts],
            filters: [.userDID],
            citations: true
        )

    case .strainEducation:
        // "Tell me about Blue Dream"
        return .init(
            sources: [.cannabisKB],
            augment: .withUserPreferences,
            citations: false
        )

    case .recommendation:
        // "What should I try next?"
        return .init(
            sources: [.localReceipts, .cannabisKB, .circleAggregated],
            reasoning: .collaborativeFiltering,
            citations: true
        )

    case .dispensarySearch:
        // "Where to buy in SF?"
        return .init(
            sources: [.dispensaryDB, .circleShared],
            location: .userLocation,
            citations: true
        )
    }
}
```

---

### Context Window Management

**Challenge:** Claude has 200K token context, but we need to be selective

**Strategy:**

```swift
func buildContext(for query: String, userDID: String) async throws -> String {
    var context = ""

    // 1. User's recent memories (most relevant)
    let recentSessions = try await fetchRecentSessions(
        userDID: userDID,
        limit: 50,
        since: Date().addingTimeInterval(-90 * 86400)  // Last 90 days
    )
    context += formatSessions(recentSessions)  // ~10K tokens

    // 2. Aggregate stats
    let stats = try await computeUserStats(userDID: userDID)
    context += formatStats(stats)  // ~1K tokens

    // 3. Circle insights (if opt-in)
    if userPrefersCircleInsights {
        let circleData = try await fetchCircleAggregates(userDID: userDID)
        context += formatCircleData(circleData)  // ~5K tokens
    }

    // 4. Relevant cannabis knowledge (RAG)
    let relevantKnowledge = try await retrieveRelevantKB(query: query)
    context += relevantKnowledge  // ~20K tokens

    // Total: ~35K tokens (well under limit)
    return context
}
```

---

### Cannabis Knowledge Base (RAG)

**Knowledge sources (must use licensed/legal sources):**

1. **Strain databases** (3,000+ strains)
   - Licensed API access (e.g., Leafly API with proper terms)
   - Strain genetics, effects, terpene profiles
   - **NOT scraped data** - use licensed APIs or user-contributed datasets

2. **Academic research**
   - PubMed papers on cannabinoids/terpenes
   - Clinical studies (properly cited)
   - Public domain educational materials

3. **General cannabis education** (NOT step-by-step cultivation)
   - High-level cultivation concepts (legal jurisdiction context only)
   - Consumption methods overview
   - Harm reduction principles

4. **Brand/dispensary data** (public, licensed)
   - Public menus via licensed APIs
   - Aggregated product information (with proper ToS compliance)

**Legal compliance:** Do NOT scrape data in violation of Terms of Service. Use licensed APIs or public datasets only.

**Vector embedding strategy:**

```swift
// Embed knowledge base chunks
let embeddings = try await generateEmbeddings(knowledgeChunks)

// Store in vector DB (local SQLite with embeddings)
try await storeEmbeddings(embeddings, in: vectorDB)

// At query time: retrieve top-k relevant chunks
let query = "What terpene causes relaxation?"
let queryEmbedding = try await generateEmbedding(query)
let topChunks = try await vectorDB.similaritySearch(queryEmbedding, k: 10)

// Add to Claude context
let context = topChunks.map { $0.text }.joined(separator: "\n\n")
```

---

## Dispensary Intelligence Features

### Consumer View

**Query:** *"What's trending at dispensaries near me?"*

**Agent response:**
```
**Top 5 products this week (SF Bay Area):**

1. **Jeeter Pre-rolls** (Sativa)
   - 47% of dispensaries report high demand
   - $15-20/pack (5 pre-rolls)
   - Your friends: 3 tried it, avg 4.2★

2. **STIIIZY Pods** (Various strains)
   - Vape cartridges, super popular
   - $40-50/1g pod
   - You haven't tried yet—want a recommendation?

3. **Kiva Camino Gummies** (Microdose)
   - 5mg THC per gummy, precise dosing
   - Your friend Ben loves these (rated 5★)

4. **Cookies Cereal Milk** (Flower)
   - New drop, selling out fast
   - $50-60/8th
   - High demand (order online to reserve)

5. **Raw Garden Live Resin** (Concentrate)
   - Premium dabs, terpene-rich
   - $30-40/g

📊 Data from 24 dispensaries + your Circle
```

---

### Dispensary View (B2B Product)

**Dashboard metrics:**

```
┌──────────────────────────────────────────────────────┐
│  Cookies SF - Product Performance (Last 30 Days)     │
├──────────────────────────────────────────────────────┤
│                                                       │
│  Top 5 Re-purchased Products:                        │
│  1. Blue Dream (Flower)  - 67% repurchase rate       │
│  2. Gelato (Flower)      - 61% repurchase rate       │
│  3. Wedding Cake (Flower) - 58% repurchase rate      │
│                                                       │
│  Underperforming Products:                           │
│  1. Sour Diesel         - 23% repurchase (⚠️ quality issue?) │
│  2. GDP                 - 19% repurchase (⚠️ restock?)    │
│                                                       │
│  Customer Insights (Opted-in users: 127):            │
│  • Most common effect tags: "relaxed" (43%), "happy" (38%)   │
│  • Avg rating: 4.2★                                  │
│  • Peak purchase times: Fri-Sat 5-8pm               │
│                                                       │
│  Opportunities:                                      │
│  📈 Stock more Blue Dream (sellout rate: 92%)        │
│  📈 Promote Gelato to Sour Diesel buyers (similar profile) │
│  📉 Investigate Sour Diesel quality (low ratings)    │
│                                                       │
└──────────────────────────────────────────────────────┘
```

**Privacy guarantee:**
- Only aggregate insights (n ≥ 75 threshold)
- No individual user data
- Opt-in required from consumers

---

## API Design

### Agent Query Endpoint

**POST** `/v1/agent/query`

**Request:**
```json
{
    "query": "What strains made me anxious?",
    "user_did": "did:buds:5dGHK7P9mN",
    "include_circle": false,  // Opt-in to Circle insights
    "max_citations": 10
}
```

**Response (required contract):**
```json
{
    "answer": "Based on your 47 logged sessions...",
    "citations": [
        {
            "type": "receipt",  // or "kb" for knowledge base
            "receipt_cid": "bafyreiabc123...",  // for type=receipt
            "snippet": "Sour Diesel - felt anxious and paranoid",
            "claimed_time_ms": 1704844800000,  // claimed_time_ms (not timestamp)
            "relevance": 0.92
        },
        {
            "type": "kb",
            "source_name": "PubMed Study",
            "url": "https://pubmed.ncbi.nlm.nih.gov/12345",
            "title": "THC and Anxiety: A Review",
            "chunk_id": "pmid-12345-abstract"
        }
    ],
    "confidence": 0.89,
    "safety_flags": ["anxiety", "substance_interaction"],  // e.g., driving, mixing, medical
    "suggested_followups": [
        "What are good alternatives to Sour Diesel?",
        "How can I reduce anxiety when consuming?"
    ]
}
```

**Citation types:**
- `receipt`: User's logged session (CID + snippet + claimed_time_ms)
- `kb`: Knowledge base source (name + URL/title + chunk ID)

**Required fields:** All responses MUST include citations array (even if empty) and safety_flags array.

---

### Citation Format

**Every factual claim links back to a receipt:**

```markdown
You experienced anxiety with **Sour Diesel** (3/3 sessions).

[📄 Session: Dec 3, 2024](buds://receipt/bafyreiabc123)
```

**Tapping citation opens the receipt in-app**

---

## Safety & Disclaimers

### Medical Advice Guardrails

**What Agent CAN do:**
✅ Share general educational harm reduction information
✅ Explain cannabinoid/terpene effects (educational context)
✅ Suggest strains based on YOUR logged preferences (personal data analysis)
✅ Explain general responsible consumption principles

**What Agent CANNOT and MUST NOT do:**
❌ Diagnose medical conditions
❌ Prescribe cannabis for medical use or specific health outcomes
❌ Replace professional medical advice
❌ Make health claims ("cannabis cures/treats condition X")
❌ Provide actionable cultivation instructions (how-to grow guides)
❌ Recommend specific dosages for medical purposes
❌ Give advice that contradicts "consult a doctor" for health questions

**Disclaimer (shown on first Agent use):**

```
Buds Agent provides educational information about cannabis
based on your logged experiences and cited general knowledge.

IMPORTANT DISCLAIMERS:
• NOT medical advice - cannot diagnose or treat conditions
• NOT legal advice - check your jurisdiction's laws
• NOT cultivation instructions - provided for educational context only
• Harm reduction info is educational, not prescriptive

By using Agent:
• You confirm you are 21+ (or legal age in your jurisdiction)
• You confirm cannabis is legal in your jurisdiction
• You understand Agent sends your data to AI provider ([Provider Name])
• You agree this is educational assistance only

Consult licensed professionals for medical or legal questions.
```

---

## Implementation Plan

### Phase 1: Device-Context Agent (v0.1 - Sends Context to Remote LLM)

**IMPORTANT PRIVACY NOTE:** Phase 1 sends receipt-derived context to a remote LLM API (DeepSeek/Qwen/Kimi). Users MUST explicitly opt-in with clear disclosure.

**Required user consent:**
```swift
// First-time Agent use
AlertView {
    title: "Enable AI Assistant?"
    message: """
    Buds Agent can answer questions about your logged sessions using AI.

    Privacy notice:
    • Your receipts are sent to [LLM Provider] for analysis
    • Data is NOT stored by the LLM provider (ephemeral processing)
    • You can disable Agent anytime in Settings

    Turn on Agent?
    """
    actions: ["Enable", "Not Now"]
}

// Settings toggle
Toggle("Enable AI Assistant", isOn: $agentEnabled)
InfoText("When ON, your session data is sent to AI provider for queries. When OFF, Agent is disabled.")
```

**Implementation:**

```swift
class BudsAgent {
    func query(_ prompt: String) async throws -> AgentResponse {
        // 0. Check user opt-in
        guard UserDefaults.standard.bool(forKey: "agentEnabled") else {
            throw AgentError.disabled("Agent is OFF. Enable in Settings → Privacy → AI Assistant")
        }

        // 1. Load user's receipts
        let receipts = try await ReceiptManager.shared.fetchAll()

        // 2. Build context
        let context = buildContextFromReceipts(receipts)

        // 3. Call LLM API (DeepSeek/Qwen/Kimi - NOT Claude in v0.1)
        // Uses pluggable LLMProvider interface
        let response = try await llmProvider.complete(
            prompt: prompt,
            system: CANNABIS_ASSISTANT_SYSTEM_PROMPT,
            context: context
        )

        // 4. Parse citations
        let citations = extractCitations(response)

        return AgentResponse(
            answer: response.text,
            citations: citations,
            confidence: response.confidence
        )
    }
}
```

### Phase 2: RAG + Knowledge Base (v0.2)

- Embed cannabis knowledge base
- Vector similarity search
- Hybrid retrieval (keyword + semantic)

### Phase 3: Circle Insights (v0.3)

- Aggregate Circle data (privacy-preserving)
- Collaborative filtering recommendations
- "Friends who liked X also liked Y"

### Phase 4: Dispensary Intelligence (v1.0)

- B2B dashboard for dispensaries
- Product performance analytics
- Market trend insights

---

## Cost Estimation (Evergreen - Update Regularly)

**LLM API pricing (as of document date, subject to change):**

| Provider | Input ($/M tokens) | Output ($/M tokens) | Notes |
|----------|-------------------|---------------------|-------|
| **DeepSeek** | ~$0.14 | ~$0.28 | Recommended for v0.1 (budget-friendly) |
| **Qwen 2.5** | ~$0.18 | ~$0.35 | Alternative option |
| **Kimi K2** | ~$0.20 | ~$0.40 | Solid performance |
| Claude Sonnet | ~$3.00 | ~$15.00 | Premium option (20x cost vs DeepSeek) |

**Note:** These prices are illustrative examples from December 2025. **Verify current pricing** before making decisions. Pricing changes frequently.

**Estimated per-query cost (using DeepSeek as example):**
- Context: ~35K tokens → ~$0.005
- Output: ~500 tokens → ~$0.0001
- **Total: ~$0.005 per query** (rough estimate)

**Monthly estimate (10K users × 10 queries/month):**
- 100K queries/month × $0.005 = ~$500/month (DeepSeek)
- 100K queries/month × $0.015 = ~$1,500/month (Claude) - for comparison

**Cost optimization strategies:**
- Cache common queries (strain education, terpene explanations)
- Use streaming for better UX
- Monitor actual usage and costs (don't rely on estimates alone)

---

## Future Enhancements

### Voice Interface

```swift
"Hey Buds, what should I smoke for a creative session?"
→ Voice input → Agent query → Voice output
```

### Multimodal Analysis

```swift
// Photo of flower → Identify strain
let image = capturedPhoto
let analysis = try await Agent.analyzeFlower(image)
// "This appears to be a sativa-dominant hybrid based on bud structure..."
```

### Predictive Recommendations

```swift
// "You usually smoke Blue Dream on Friday evenings for relaxation.
// Want me to add it to your shopping list?"
```

---

**Next:** See [UX_FLOWS.md](./UX_FLOWS.md) for detailed user experience flows.
