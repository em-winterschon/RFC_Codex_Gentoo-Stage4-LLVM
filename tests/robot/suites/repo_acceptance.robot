*** Settings ***
Documentation       Repository acceptance smoke tests for the layered test strategy.
Library             OperatingSystem
Library             String


*** Variables ***
${REPO_ROOT}        ${CURDIR}/../../..


*** Test Cases ***
Testing Strategy Document Exists
    ${strategy}=    Get File    ${REPO_ROOT}/docs/TESTING-STRATEGY.md
    Should Contain    ${strategy}    Layered Test Model
    Should Contain    ${strategy}    Robot Framework acceptance
    Should Contain    ${strategy}    Jenkins Pipeline

Python Unit Test Runner Exists
    File Should Exist    ${REPO_ROOT}/tests/python/run-tests.sh
    File Should Exist    ${REPO_ROOT}/tests/python/test_service_validator.py
    ${unit_test}=    Get File    ${REPO_ROOT}/tests/python/test_service_validator.py
    Should Contain    ${unit_test}    unittest.TestCase

Shell Entry Point Includes Python And Robot Layers
    ${run_tests}=    Get File    ${REPO_ROOT}/tests/shell/run-tests.sh
    Should Contain    ${run_tests}    tests/python/run-tests.sh
    Should Contain    ${run_tests}    tests/robot/run-tests.sh
    Should Contain    ${run_tests}    test_testing_strategy_scaffold.sh
