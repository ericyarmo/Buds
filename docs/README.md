# Buds Documentation

This directory contains all technical documentation for the Buds app.

## Directory Structure

### `/architecture/`
Core technical architecture and specifications:
- `ARCHITECTURE.md` - Overall system architecture and layers
- `DATABASE_SCHEMA.md` - SQLite database schema and migrations (current: v8)
- `E2EE_DESIGN.md` - End-to-end encryption design
- `PRIVACY_ARCHITECTURE.md` - Privacy and security architecture
- `RECEIPT_SCHEMAS.md` - UCR (Universal Cannabis Receipt) schemas
- `CANONICALIZATION_SPEC.md` - CBOR canonicalization specification
- `JAR_ARCHITECTURE.md` - Jar sync architecture (relay envelope, sequences, CIDs)
- `BUDS_CRYPTO_KEY_MAP.md` - Complete crypto key inventory

### `/planning/`
Development plans and phase completion records:
- `R1_MASTER_PLAN.md` - R1 release master plan
- `PHASE_*_COMPLETE.md` - Completion records for each phase
- **Phase 10.3 (Current):**
  - `PHASE_10.3_FINAL_SUMMARY.md` - **START HERE** - Current roadmap (Modules 0.1-10)
  - `PHASE_10.3_JAR_SYNC_HARDENED.md` - Master implementation plan (relay envelope architecture)
  - `PHASE_10.3_CRYPTO_ADDENDUM.md` - Crypto blind spots & fixes (TOFU, multi-device, CBOR)
  - `PHASE_10.3_EDGE_CASE_AUDIT.md` - Distributed systems edge cases
- `PHASE_9A_TESTING_FLOW.md` - Phase 9a testing documentation (moved to /testing/)
- `phase9-plan.md` - Phase 9 implementation plan
- `phase9b-plan.md` - Phase 9b (Shelf View) plan
- `PHASE_9_AUDIT_SUMMARY.md` - Phase 9 audit and risk analysis

### `/testing/`
Testing guides and procedures:
- `PHASE_9A_TESTING_FLOW.md` - Phase 9a comprehensive testing flow
- `APNS_TESTING_GUIDE.md` - APNS push notification testing
- `QUICK_TEST_INSTRUCTIONS.md` - Quick smoke test instructions
- `TESTING_GUIDE.md` - General testing guide

### `/features/`
Feature-specific planning documents:
- `MAP_VIEW_PLAN.md` - Location/map view feature plan
- `TIERED_STORAGE_PLAN.md` - Tiered storage architecture plan
- `SCALE_ANALYSIS.md` - Scalability analysis and metrics

### `/design/`
UI/UX design specifications:
- `DESIGN_SYSTEM.md` - Design system (colors, typography, spacing)
- `UX_MAKEOVER_SPEC.md` - UX improvements and redesign spec
- `DEBUG_SYSTEM.md` - Debug console and developer tools

## Navigation Tips

### For New Contributors
1. Start with `/architecture/ARCHITECTURE.md` - Understand the 4-layer system
2. Read `/architecture/DATABASE_SCHEMA.md` - Learn the data model
3. Review `/planning/R1_MASTER_PLAN.md` - See the roadmap

### For Agents/LLMs
- **Start Here**: `/planning/PHASE_10.3_FINAL_SUMMARY.md` - Current roadmap (Phase 10.3 Modules 0.1-10)
- **System Architecture**: See `/architecture/JAR_ARCHITECTURE.md` - Jar sync (relay envelope, sequences, CIDs)
- **Current Phase**: Phase 10.3 - Modules 2/10 complete (28-38 hours remaining)
- **Testing**: See `/testing/PHASE_9A_TESTING_FLOW.md` for comprehensive test suite
- **Features**: Feature-specific docs in `/features/`
- **CBOR Policy**: `CBOR_POLICY.md` (root level) - **CRITICAL** - Library pinning (never upgrade SwiftCBOR)

### For Debugging
- `/design/DEBUG_SYSTEM.md` - Debug console usage
- `/testing/QUICK_TEST_INSTRUCTIONS.md` - Fast smoke tests
- `/planning/PHASE_*_COMPLETE.md` - See what's implemented per phase

## Document Naming Conventions

- `UPPERCASE_NAME.md` - Technical specifications and guides
- `lowercase-name.md` - Implementation plans
- `Phase_X_COMPLETE.md` or `PHASE_X_COMPLETE.md` - Phase completion records

## Quick Reference

| Need to... | See... |
|------------|--------|
| Understand the system | `/architecture/ARCHITECTURE.md` |
| Add a feature | `/planning/R1_MASTER_PLAN.md` + relevant phase plan |
| Fix a bug | `/architecture/DATABASE_SCHEMA.md` + debug console |
| Run tests | `/testing/PHASE_9A_TESTING_FLOW.md` |
| Design UI | `/design/DESIGN_SYSTEM.md` |
| Check what's done | `/planning/PHASE_*_COMPLETE.md` |

## Contributing

When adding documentation:
1. Place in appropriate subfolder
2. Use clear, descriptive filenames
3. Add entry to this README if it's a major doc
4. Follow existing naming conventions
