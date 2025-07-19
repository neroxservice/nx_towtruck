CREATE TABLE IF NOT EXISTS parking_tickets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(64),
    plate VARCHAR(10),
    bought_at DATETIME,
    duration_hours INT,
    position TEXT NULL,
    heading FLOAT NULL,
    model TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE owned_vehicles ADD COLUMN IF NOT EXISTS position TEXT NULL;

INSERT IGNORE INTO jobs (name, label) VALUES ('towtrucker', 'Towtrucker');

INSERT IGNORE INTO job_grades (job_name, grade, name, label, salary) VALUES
('towtrucker', 0, 'junior', 'Junior Towtrucker', 400),
('towtrucker', 1, 'senior', 'Senior Towtrucker', 800),
('towtrucker', 2, 'boss', 'Towtrucker Boss', 1200);
