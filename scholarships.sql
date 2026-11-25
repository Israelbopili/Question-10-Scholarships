-- ICT371 QUESTION 10: SCHOLARSHIP APPLICATION ASSESSMENT
DROP SCHEMA IF EXISTS q10_scholarships CASCADE;
CREATE SCHEMA q10_scholarships;
SET search_path TO q10_scholarships;

CREATE TABLE students(
 student_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 student_number VARCHAR(30) NOT NULL UNIQUE,full_name VARCHAR(120) NOT NULL
);
CREATE TABLE applications(
 application_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 student_id BIGINT NOT NULL REFERENCES students(student_id),
 age_at_application INTEGER NOT NULL CHECK(age_at_application>0),
 monthly_income NUMERIC(12,2) NOT NULL CHECK(monthly_income>=0),
 average_mark NUMERIC(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),
 submitted_on DATE NOT NULL,
 status VARCHAR(10) NOT NULL DEFAULT 'PENDING'
 CHECK(status IN ('PENDING','APPROVED','REJECTED'))
);
CREATE TABLE decision_audit(
 audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 application_id BIGINT NOT NULL REFERENCES applications(application_id),
 old_status VARCHAR(10),new_status VARCHAR(10) NOT NULL,
 changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO students(student_number,full_name) VALUES
('ST001','Applicant One'),('ST002','Applicant Two'),('ST003','Applicant Three');
INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on,status) VALUES
(1,18,3000,70,CURRENT_DATE,'PENDING'),
(1,25,2500,85,CURRENT_DATE,'PENDING'),
(2,17,2000,90,CURRENT_DATE,'PENDING'),
(2,22,3001,80,CURRENT_DATE,'PENDING'),
(3,24,2800,69.99,CURRENT_DATE,'PENDING'),
(3,26,1000,95,CURRENT_DATE,'PENDING');

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INTEGER,p_income NUMERIC,p_mark NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
  RAISE EXCEPTION 'All eligibility inputs are required';
 END IF;
 IF p_age<=0 OR p_income<0 OR p_mark<0 OR p_mark>100 THEN
  RAISE EXCEPTION 'Invalid age, income or mark';
 END IF;
 RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70;
END; $$;

CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_age INTEGER; v_income NUMERIC(12,2); v_mark NUMERIC(5,2); v_status VARCHAR(10);
BEGIN
 SELECT age_at_application,monthly_income,average_mark,status
 INTO v_age,v_income,v_mark,v_status
 FROM applications WHERE application_id=p_application_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application ID %',p_application_id; END IF;
 IF v_status<>'PENDING' THEN RAISE EXCEPTION 'Application has already been assessed'; END IF;
 UPDATE applications SET status=CASE
  WHEN fn_scholarship_eligible(v_age,v_income,v_mark) THEN 'APPROVED'
  ELSE 'REJECTED' END
 WHERE application_id=p_application_id;
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_decision()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.status IS DISTINCT FROM NEW.status THEN
  INSERT INTO decision_audit(application_id,old_status,new_status)
  VALUES(NEW.application_id,OLD.status,NEW.status);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_audit_decision AFTER UPDATE ON applications
FOR EACH ROW EXECUTE FUNCTION fn_audit_decision();

CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number,s.full_name,a.average_mark,a.status
FROM applications a JOIN students s USING(student_id)
WHERE a.status='APPROVED';

CREATE INDEX idx_applications_status_submitted
ON applications(status,submitted_on);
EXPLAIN SELECT * FROM applications WHERE status='PENDING'
 AND submitted_on BETWEEN CURRENT_DATE-30 AND CURRENT_DATE;

CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql AS $$
DECLARE a RECORD;
BEGIN
 FOR a IN SELECT application_id FROM applications WHERE status='PENDING'
          ORDER BY application_id LOOP
  CALL pr_assess_application(a.application_id);
 END LOOP;
END; $$;

CALL pr_assess_pending();
SELECT * FROM applications ORDER BY application_id;
SELECT * FROM decision_audit ORDER BY audit_id;
SELECT * FROM v_approved_applicants;

-- pg_cron weekly Monday at 08:00:
-- SELECT cron.schedule('assess-pending-weekly','0 8 * * 1',
-- 'CALL q10_scholarships.pr_assess_pending();');
