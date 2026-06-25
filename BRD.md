Business Requirements Document (BRD)
Project: Soul Matching Platform
Document Version: 1.0.0
Target Audience: Engineering Team, Product Managers, Database Administrators, Stakeholders
1. Executive Summary & Business Objectives
1.1 Project Purpose
The Soul Matching Platform is an enterprise-grade, AI-driven matrimonial platform designed to automate, protect, and enhance the matchmaking lifecycle. Moving away from traditional, manual browsing models, the platform introduces a privacy-first, automated matchmaking engine that pairs individuals into a temporary, exclusive communication environment based on psychological alignment and core demographic traits.
1.2 Strategic Objectives
Instant Automation: Minimize user time-to-match using automated background database workers.
Privacy by Design: Limit exposure of user data until a secure, structural match is algorithmically validated.
Deep Engagement: Enhance post-match interactions using localized Generative AI communication consulting.
Enterprise Security: Enforce strict Row-Level Security (RLS) and verified role-based tokens for data governance.
2. System Architecture & High-Level Tech Stack
The architecture follows a decoupled, cloud-native paradigm to guarantee fast delivery, effortless rendering, and high scalability:
Frontend Layer: Flutter (Web & Mobile ecosystem) deployed on Vercel.
Backend API Layer: FastAPI (Python) hosted on Render.
Database & Realtime Layer: Supabase (PostgreSQL) handling authentication, data storage, automated database triggers, and low-latency websocket streams.
3. Functional Requirements
3.1 User Onboarding & Dynamic Profiling
Profile Acquisition: The system must capture explicit user dimensions, including but not limited to: First Name, Height, Location/City, Marital Status, Educational Attainment, and Psychological Profiling Answers.
State Management: Users are assigned an initial account_status of 'pending' immediately upon completing profile creation.
3.2 "The Hunter" Automated Matchmaking Engine
Execution Paradigm: The matching mechanism runs entirely inside the database layer as a PostgreSQL BEFORE INSERT OR UPDATE trigger to prevent race conditions or thread collision.
Atomic Locking: The engine must utilize atomic queuing queries (FOR UPDATE SKIP LOCKED) to ensure a single pending candidate is never simultaneously mapped to two separate matching processes.
Exclusivity Logic: Once an alignment is detected:
A row is securely injected into the matches table.
The compatibility rating is hardcoded or algorithmically set (e.g., 99%).
Both users have their account_status updated simultaneously to 'matched'.
3.3 The Focus Room (Exclusive Chat Environment)
The Countdown Chamber: Matched users transition to an exclusive "Focus Room" governed by a hard 24-hour expiration countdown (expires_at).
Profile Exposure: Users can securely view their partner’s complete profile parameters via verified database reads.
Realtime Chat Streaming: The chat interface must completely abandon static pulling models, executing via clean Supabase Streams connected directly to the messages table.
UI Controls & Fluidity:
The UI must automatically invoke list scrolling mechanisms to focus on the newest message bubble upon stream updates.
Support native Arabic timestamp formatting (e.g., 10:45 ص / 05:12 م).
Render read-receipt checkmarks synced to delivery tracking flags.
3.4 Live Multi-Trigger Notification Engine
The system enforces a background signaling infrastructure that writes events directly to a centralized notifications table:
Trigger Source
Event
Recipient
Payload Context
matches Table Insert
Match Success
Both Paired Users
"تم ربط التوافق الروحي بنجاح!"
messages Table Insert
New Message Sent
Message Recipient Only
"لديك رسالة جديدة في غرفة التركيز"

Active Chat Suppression: The frontend must natively catch stream updates and actively suppress/auto-read notifications if the recipient is currently looking at that specific active match_id chat interface.
The Notification Center: A reusable NotificationBell widget with responsive unread counter badges must be globally shared across application appbars, redirecting users to a glassmorphic notification cleaning center.
3.5 AI Post-Marriage Counselor (Premium Feature)
Functional Target: To guide early-stage communications using generative psychological advice.
API Route: POST /api/post-marriage-counselor/{match_id} managed via the FastAPI service.
Execution Workflow:
The endpoint fetches the underlying psychological properties of both matched participants.
Runs an orchestration prompt through Gemini Pro.
Produces advanced, localized, highly respectful relationship consulting text in Arabic.
The frontend streams this content smoothly into a premium, golden-gradient frosted-glass bottom sheet container complete with retrieval animations.
3.6 Secure Admin Analytics Dashboard
Route Isolation: A restricted visualization portal (/admin) presenting accurate system status metrics.
Core Metrics Tracked:
Volumetric user tracking (Total Users, Pending Queue vs. Matched Count).
Active operational focus rooms.
Average algorithmic compatibility values across the platform.
Administrative Controls: Includes a manual command interface to bypass automated timers and force run the matchmaking loop cycle on demand.
4. Non-Functional & Security Requirements
4.1 Security & Data Governance
Row-Level Security (RLS): Supabase RLS policies must be explicitly enabled on all core tables (profiles, matches, messages, notifications).
Chat Access Rule: A user can only select or insert data into the messages table if their active auth.uid() matches either user1_id or user2_id within the corresponding matches record.
JWT Token Validation: The FastAPI admin endpoint must extract, decode, and explicitly validate the Supabase bearer JWT token before rendering analytics data. Access is denied unless the token's profile maps to is_admin = true.
Environment Guarding: To protect the system against exploit vectors, any demo evaluation shortcuts (such as allowing @admin.com email strings to view dashboard tools) must be compiled strictly behind Flutter’s native kDebugMode flag, completely defaulting back to server-side boolean column verification in release builds.
4.2 Performance & Reliability
State Preservation: Frontend components must initialize database streams exactly once inside lifecycle setup scopes (initState) to eliminate display flickering, view dropouts, or unexpected re-initialization behaviors when text states switch.
Security Definer Isolation: High-priority internal database trigger functions must execute with explicit SECURITY DEFINER privileges, allowing automated system workers to scan independent rows while safely bypassing default restrictive RLS boundaries.
5. Implementation Architecture Matrix



  +-----------------------------------------------------------+
  |                   FLUTTER FRONTEND                        |
  | (Vercel: Onboarding, Focus Room, Realtime Chat Stream)    |
  +-----------------------------+-----------------------------+
                                |
             Restful Actions    |   Realtime WebSocket Streams
             & Admin Metrics    |   & Auth Channels
                                |
  +-----------------------------v---+   +---------------------+
  |          FASTAPI API            |   |   SUPABASE ENGINE   |
  |     (Render Deployment)         |   | (PostgreSQL Core)   |
  |                                 |   |                     |
  |  * POST /api/counselor          |   |  * RLS Protections  |
  |    (Gemini Pro Integration)     |   |  * Chat Streaming   |
  |  * GET  /api/admin/stats        +--->  * "The Hunter"     |
  |    (JWT Authenticated)          |   |    Database Trigger |
  +---------------------------------+   +---------------------+


6. Verification and Acceptance Criteria
Zero Warning Compilation: Frontend execution logs must pass clean validation runs (flutter analyze) with zero errors or warnings before deployments are authorized.
End-to-End Match Validation:
User A enters the queue (pending).
User B enters the queue (pending).
The trigger catches the change instantly, shifting both profiles to matched, and injects a synchronized record to the matches interface.
Both clients instantly render the active room view without data dropouts or screen flickering.
