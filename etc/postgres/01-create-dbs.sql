-- create per-service DBs for local development
CREATE DATABASE hotelier_availability;
CREATE DATABASE hotelier_accommodation;
CREATE DATABASE hotelier_identity;
CREATE DATABASE hotelier_rating;
CREATE DATABASE hotelier_reservation;

-- set owner to the postgres user created by env (hotelier)
ALTER DATABASE hotelier_availability OWNER TO hotelier;
ALTER DATABASE hotelier_accommodation OWNER TO hotelier;
ALTER DATABASE hotelier_identity OWNER TO hotelier;
ALTER DATABASE hotelier_rating OWNER TO hotelier;
ALTER DATABASE hotelier_reservation OWNER TO hotelier;