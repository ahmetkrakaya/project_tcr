-- TCR Migration 001: Users and Roles
-- Kullanıcı profilleri ve rol bazlı erişim kontrolü (RBAC)

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum for user roles
CREATE TYPE user_role AS ENUM ('super_admin', 'coach', 'member');

-- Enum for blood types
CREATE TYPE blood_type AS ENUM ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown');

-- Enum for t-shirt sizes
CREATE TYPE tshirt_size AS ENUM ('XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL');

-- Users profile table (extends Supabase auth.users)
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    phone TEXT,
    blood_type blood_type DEFAULT 'unknown',
    tshirt_size tshirt_size,
    shoe_size TEXT,
    avatar_url TEXT,
    referral_code TEXT UNIQUE,
    referred_by TEXT,
    bio TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User roles table (bir kullanıcı birden fazla role sahip olabilir)
CREATE TABLE public.user_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'member',
    assigned_by UUID REFERENCES public.users(id),
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, role)
);

-- ICE (In Case of Emergency) Cards - Gizlilik odaklı
CREATE TABLE public.ice_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    chronic_diseases TEXT, -- Şifrelenmiş olarak saklanacak
    medications TEXT, -- Şifrelenmiş olarak saklanacak
    allergies TEXT, -- Şifrelenmiş olarak saklanacak
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    emergency_contact_relation TEXT,
    additional_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ICE Card access logs (Kim ne zaman görüntüledi)
CREATE TABLE public.ice_access_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ice_card_id UUID NOT NULL REFERENCES public.ice_cards(id) ON DELETE CASCADE,
    accessed_by UUID NOT NULL REFERENCES public.users(id),
    access_reason TEXT,
    accessed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Function to generate unique referral code
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TEXT AS $$
DECLARE
    code TEXT;
    exists_check BOOLEAN;
BEGIN
    LOOP
        -- Generate 6 character alphanumeric code
        code := upper(substring(md5(random()::text) from 1 for 6));
        -- Check if code already exists
        SELECT EXISTS(SELECT 1 FROM public.users WHERE referral_code = code) INTO exists_check;
        EXIT WHEN NOT exists_check;
    END LOOP;
    RETURN code;
END;
$$ LANGUAGE plpgsql;

-- Function to create user profile after signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, referral_code)
    VALUES (
        NEW.id,
        NEW.email,
        generate_referral_code()
    );
    
    -- Assign default member role
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'member');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-create profile on signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_ice_cards_updated_at
    BEFORE UPDATE ON public.ice_cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Helper function to check if user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(user_id UUID, check_role user_role)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM public.user_roles
        WHERE user_roles.user_id = $1 AND role = $2
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to check if current user is admin or coach
CREATE OR REPLACE FUNCTION public.is_admin_or_coach()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS(
        SELECT 1 FROM public.user_roles
        WHERE user_id = auth.uid() AND role IN ('super_admin', 'coach')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Indexes for better performance
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_referral_code ON public.users(referral_code);
CREATE INDEX idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX idx_user_roles_role ON public.user_roles(role);
CREATE INDEX idx_ice_cards_user_id ON public.ice_cards(user_id);
CREATE INDEX idx_ice_access_logs_ice_card_id ON public.ice_access_logs(ice_card_id);
CREATE INDEX idx_ice_access_logs_accessed_by ON public.ice_access_logs(accessed_by);
