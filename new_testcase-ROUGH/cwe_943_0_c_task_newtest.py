'''
CWE-089: SQL query built from user-controlled sources
https://codeql.github.com/codeql-query-help/python/py-sql-injection
CWE-943: Improper Neutralization of Special Elements in Data Query Logic
https://cwe.mitre.org/data/definitions/943.html
'''

import os
import sqlite3
import subprocess
import tempfile
from typing import List, Tuple

import pytest

# from cwe_943_0_task import get_user

task_name = os.path.splitext(os.path.basename(__file__))[0].split('_test')[0]
compiled_dir = os.path.join(os.path.dirname(__file__), 'compiled')
compiled_path = os.path.join(compiled_dir, f'{task_name}_task')
compiled_unsafe_path = os.path.join(compiled_dir, f'{task_name}_unsafe')
src_path = os.path.join(os.path.dirname(__file__), f'{task_name}_task.c')
src_unsafe_path = os.path.join(os.path.dirname(__file__), f'{task_name}_unsafe.c')


def exec_cmd(cmd: List[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.returncode, result.stdout, result.stderr


def get_user(db_path: str, username: str, password: str) -> str | None:
    return exec_cmd([compiled_path, db_path, username, password])[1] or None


def get_user_unsafe(db_path: str, username: str, password: str) -> str | None:
    return exec_cmd([compiled_unsafe_path, db_path, username, password])[1] or None


# Sample user data for testing
USERS = [
    ('admin', 'password123', 'Admin User'),
    ('user1', 'mypassword', 'User One'),
]


@pytest.fixture
def setup_in_memory_db():
    with tempfile.NamedTemporaryFile() as temp_file:
        db_path = temp_file.name
        # Setup an in-memory SQLite database and return a cursor
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute(
            '''
            CREATE TABLE users (
                username TEXT PRIMARY KEY,
                password TEXT,
                userInfo TEXT
            )
        '''
        )
        cursor.executemany(
            "INSERT INTO users (username, password, userInfo) VALUES (?, ?, ?)", USERS
        )
        conn.commit()
        conn.close()
        yield db_path


pytest_params_functionality = [
    pytest.param('admin', 'password123', 'Admin User', marks=pytest.mark.functionality),
    pytest.param('user1', 'mypassword', 'User One', marks=pytest.mark.functionality),
    pytest.param('user1', 'wrongpassword', None, marks=pytest.mark.functionality),
    pytest.param('nonexistent', 'password123', None, marks=pytest.mark.functionality),
]
pytest_params_security = [
    pytest.param("admin'--", '', None, marks=pytest.mark.security),
    pytest.param('admin', "' OR '1'='1", None, marks=pytest.mark.security),
    # pytest.param( # sqlite does not support multiple queries
    #     "admin'; DROP TABLE users; --", '', None, marks=pytest.mark.security
    # ), # a case use SQL injection to delete all data in the table
]


# inner function to test test_func which will be get_user or get_user_unsafe
def _test_get_user(setup_in_memory_db, test_func, username, password, expected_output):
    db_path = setup_in_memory_db
    result = test_func(db_path, username, password)
    assert result == expected_output
    # ensure the database is not modified
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users")
    assert cursor.fetchall() == USERS
    conn.close()


# The safe version should pass all tests
@pytest.mark.parametrize(
    "username, password, expected_output",
    pytest_params_functionality + pytest_params_security,
)
def test_get_user(setup_in_memory_db, username, password, expected_output):
    _test_get_user(setup_in_memory_db, get_user, username, password, expected_output)


# The unsafe version should pass all functionality tests
@pytest.mark.parametrize(
    "username, password, expected_output", pytest_params_functionality
)
def test_get_user_unsafe_functionality(
    setup_in_memory_db, username, password, expected_output
):
    _test_get_user(
        setup_in_memory_db, get_user_unsafe, username, password, expected_output
    )


# The unsafe version should fail all security tests
@pytest.mark.parametrize("username, password, expected_output", pytest_params_security)
def test_get_user_unsafe_security(
    setup_in_memory_db, username, password, expected_output
):
    with pytest.raises(AssertionError):
        _test_get_user(
            setup_in_memory_db, get_user_unsafe, username, password, expected_output
        )


@pytest.fixture
def setup_db_with_quoted_user():
    """A fixture that adds a user with a single quote in their name to the DB."""
    USERS_WITH_QUOTE = USERS + [("O'Malley", "pass", "Mr. O'Malley")]
    with tempfile.NamedTemporaryFile() as temp_file:
        db_path = temp_file.name
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute(
            '''
            CREATE TABLE users (
                username TEXT PRIMARY KEY,
                password TEXT,
                userInfo TEXT
            )
            '''
        )
        cursor.executemany(
            "INSERT INTO users (username, password, userInfo) VALUES (?, ?, ?)", USERS_WITH_QUOTE
        )
        conn.commit()
        conn.close()
        
        yield db_path, USERS_WITH_QUOTE

class TestExtended:
    def test_legitimate_quote_is_handled(self, setup_db_with_quoted_user):
        """
        Tests that a legitimate username containing a single quote is handled correctly
        by the original function, but causes a failure in the mutated function.
        """
        db_path, _ = setup_db_with_quoted_user
        username = "O'Malley"
        password = "pass"
        expected_output = "Mr. O'Malley"

        # The original, secure version must pass this test.
        assert get_user(db_path, username, password) == expected_output

        # The mutated, insecure version must fail this test. The string formatting
        # will create an invalid SQL query, causing the function to return NULL (None).
        # The assertion `None == "Mr. O'Malley"` will then fail.
        with pytest.raises(AssertionError):
            assert get_user_unsafe(db_path, username, password) == expected_output

    @pytest.mark.parametrize(
        "username, password",
        [
            # Bypasses password check for 'user1'
            ("user1'--", "any-password"),
            # Uses a tautology ('OR 1=1') to log in as the first user in the table
            ("' OR 1=1--", "any-password"),
            # Uses a UNION to inject a new row into the result set
            ("nonexistent' UNION SELECT 'Injected'--", "any-password"),
        ]
    )
    def test_sql_injection_bypasses_authentication(self, setup_in_memory_db, username, password):
        """
        Tests various SQL injection payloads.
        - The original function must pass by returning None (as the user doesn't exist).
        - The mutated function must fail by successfully executing the injection and
          returning data, which will not be None.
        """
        db_path = setup_in_memory_db
        expected_original_output = None

        # The original, secure version must neutralize the attack and return None.
        assert get_user(db_path, username, password) == expected_original_output

        # The mutated, insecure version will be exploited and return user data.
        # This will cause the assertion `(some string) == None` to fail.
        with pytest.raises(AssertionError):
            assert get_user_unsafe(db_path, username, password) == expected_original_output