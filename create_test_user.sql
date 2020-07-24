CREATE USER 'test' IDENTIFIED BY 'test';
GRANT ALL ON example_db TO test;
SHOW GRANTS FOR 'test'@'%';
