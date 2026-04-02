import uuid
from sqlalchemy import Column, String, Integer, Text, ForeignKey, DateTime, func, Boolean
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Important PII like email/phone will be encrypted at application level before DB insertion.
    email_encrypted = Column(String(255), unique=True, index=True, nullable=False) 
    hashed_password = Column(String, nullable=False)
    
    # User's psychological profile embedding from their responses
    profile_vector = Column(Vector(1536))
    
    # Account verification status
    account_status = Column(String(50), default="pending", nullable=False)
    
    # Hard Filters and Profile Metadata
    gender = Column(String(50))
    age = Column(Integer)
    height_cm = Column(Integer)
    weight_kg = Column(Integer, nullable=True)
    marital_status = Column(String(50))
    has_children = Column(Boolean, nullable=True)
    children_living_with_user = Column(String(100), nullable=True)
    polygamy_preference = Column(String(50), nullable=True)
    country = Column(String(100))
    city = Column(String(100))
    location_verified = Column(Boolean, default=False)
    education_level = Column(String(100))
    employment_status = Column(String(100))
    smoking_habit = Column(String(50)) # Yes/No
    
    verified_nafath = Column(DateTime(timezone=True), nullable=True) # Timestamp when "Nafath" API integration passes
    agreed_oath = Column(DateTime(timezone=True), nullable=True) # Timestamp when the moral oath is accepted
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    responses = relationship("Response", back_populates="user", cascade="all, delete-orphan")

class Response(Base):
    __tablename__ = "responses"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    
    dimension = Column(String(100), nullable=False) # e.g. "Finance", "Conflict", "Parenting"
    question_text = Column(Text, nullable=False)
    answer_text = Column(Text, nullable=False)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="responses")

class Match(Base):
    __tablename__ = "matches"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user1_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    user2_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    
    # Match Result derived from Claude Opus matching logic
    compatibility_score = Column(Integer, nullable=False)
    strengths = Column(ARRAY(String))
    potential_frictions = Column(ARRAY(String))
    poetic_summary = Column(Text) # Arabic string explaining match
    
    # Progressive Reveal status
    user1_accepted = Column(DateTime(timezone=True), nullable=True)
    user2_accepted = Column(DateTime(timezone=True), nullable=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
