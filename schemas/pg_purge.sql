BEGIN;
DELETE FROM archive;
DELETE FROM analytic;
DELETE FROM domain;
DELETE FROM infrastructure;
DELETE FROM url;
DELETE FROM email;
DELETE FROM malware;
DELETE FROM search;
DELETE FROM feed;
DELETE FROM hash;
DELETE FROM rir;
DELETE FROM asn;
DELETE FROM countrycode;
COMMIT;