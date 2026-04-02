# Project: AI-Driven Matrimonial Platform (Anti-Tinder)
**Version:** 1.0.0
**Target Market:** Saudi Arabia / Conservative & Elite Demographic.

## 1. System Prompt & Agent Persona
You are a Senior Full-Stack Architect and AI Integration Expert. 
- **Rule 1:** ALWAYS refer to this `PRD.md` before generating any code or making architectural decisions.
- **Rule 2:** Ask for clarification if a user request contradicts this document.
- **Rule 3:** Prioritize security, data sanitization, and scalable database architecture above all else.

## 2. Tech Stack Requirements
- **Frontend (Mobile):** Flutter (Dart) - MUST fully support RTL (Right-to-Left) for Arabic natively.
- **Frontend (Web):** React.js or Next.js.
- **Backend/API:** Node.js (TypeScript) OR Python (FastAPI).
- **Primary Database:** PostgreSQL (for relational data, PII, auth).
- **Vector Database:** Pinecone OR pgvector (for psychological embeddings).
- **AI Models:** Claude Opus (for complex matching logic/backend) & Gemini Pro (for localized Arabic UI/Frontend copy).

## 3. UI/UX & Design Language
- **Vibe:** Elegant, calm, trustworthy, gender-neutral.
- **Color Palette:** - Primary: Deep Olive Green & Navy Blue.
  - Secondary/Background: Sand Beige & Ivory White.
  - **Constraint:** DO NOT use aggressive colors like bright red or neon pink.
- **Components:** Use conversational UI (Card swipe or chat-like interfaces) for onboarding. Avoid long, tedious web forms.

## 4. User Journey & Core Features
1. **Identity Verification:** MUST integrate with government APIs (e.g., "Nafath") before account creation. 
2. **The Oath Screen:** A mandatory screen where users accept a moral code ("I swear my intent is marriage..."). No skip button.
3. **Scenario-Based Questionnaire:** 10-15 dynamic questions covering 5 dimensions: Finance, Conflict, Parenting, Lifestyle, Boundaries.
4. **Progressive Reveal (Blind Match):** - **Constraint:** Profile pictures MUST be blurred/hidden by default.
   - Photos are ONLY revealed after a high compatibility score is reached AND both parties click "Accept".

## 5. Matchmaking Logic (RAG Architecture)
- **Data Flow:** User answers -> Backend -> Stripped of PII -> Vectorized -> Stored in Vector DB.
- **Matching:** System queries Vector DB for nearest neighbors -> Sends anonymized pair data to LLM (Expert Counselor Persona).
- **Expected LLM Output Format (Strict JSON):**
  ```json
  {
    "compatibility_score": 85,
    "strengths": ["string", "string"],
    "potential_frictions": ["string"],
    "poetic_summary": "Arabic string explaining the spiritual and intellectual match."
  }

## 6. Security & Privacy Defaults
ALL personally identifiable information (Name, National ID, Phone) MUST be encrypted at rest in PostgreSQL.

The LLM MUST NEVER receive real names or photos, only anonymized User IDs and text responses.