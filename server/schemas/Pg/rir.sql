DROP TABLE IF EXISTS rir CASCADE;
CREATE TABLE rir (
    id BIGSERIAL PRIMARY KEY NOT NULL,
    uuid uuid REFERENCES archive(uuid) ON DELETE CASCADE NOT NULL,
    rir varchar(8),
    confidence REAL,
    source uuid NOT NULL,
    severity severity,
    restriction restriction not null default 'private',
    detecttime timestamp with time zone DEFAULT NOW(),
    created timestamp with time zone DEFAULT NOW(),
    unique(uuid,rir)
);