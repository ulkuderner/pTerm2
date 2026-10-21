#include "pad_system.h"

#include <stdio.h>
#include <string.h>

#if defined(IT2PAD_HAS_IOS_SYSTEM)
#include <ios_system/ios_system.h>

int pad_ios_system(const char *command) {
    return ios_system(command);
}

int pad_ios_system_ready(void) {
    return 1;
}

void pad_ios_system_initialize(const char *home) {
    (void)home;
    initializeEnvironment();
    ios_setMiniRoot(home);
}

#else

int pad_ios_system(const char *command) {
    (void)command;
    return -1;
}

int pad_ios_system_ready(void) {
    return 0;
}

void pad_ios_system_initialize(const char *home) {
    (void)home;
}

#endif

#if defined(IT2PAD_HAS_PYTHON)

#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <unistd.h>
#include <wchar.h>
#include <Python.h>

static void capture_write(const char *text) {
    const char *path = getenv("PTERM_PY_CAPTURE");
    if (!path || !text) {
        return;
    }
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        return;
    }
    size_t length = strlen(text);
    if (length > 0) {
        (void)write(fd, text, length);
    }
    close(fd);
}

static void capture_status(const char *fallback, PyStatus status) {
    char message[512];
    snprintf(message, sizeof(message), "python: %s\n",
             (PyStatus_Exception(status) && status.err_msg) ? status.err_msg : fallback);
    capture_write(message);
}

static int install_capture(PyObject **buffer) {
    PyObject *io_module = PyImport_ImportModule("io");
    if (!io_module) {
        PyErr_Print();
        return -1;
    }
    PyObject *factory = PyObject_GetAttrString(io_module, "StringIO");
    Py_DECREF(io_module);
    if (!factory) {
        return -1;
    }
    PyObject *stream = PyObject_CallNoArgs(factory);
    Py_DECREF(factory);
    if (!stream) {
        return -1;
    }
    if (PySys_SetObject("stdout", stream) < 0 || PySys_SetObject("stderr", stream) < 0) {
        Py_DECREF(stream);
        return -1;
    }
    *buffer = stream;
    return 0;
}

static void publish_capture(PyObject *stream) {
    if (!stream) {
        return;
    }
    PyObject *value = PyObject_CallMethod(stream, "getvalue", NULL);
    if (value) {
        const char *text = PyUnicode_AsUTF8(value);
        if (text) {
            capture_write(text);
        }
        Py_DECREF(value);
    } else {
        PyErr_Clear();
    }
}

static int ensure_python(void) {
    if (Py_IsInitialized()) {
        return 0;
    }
    CFURLRef resources = CFBundleCopyResourcesDirectoryURL(CFBundleGetMainBundle());
    char resource_path[1024];
    if (!resources || !CFURLGetFileSystemRepresentation(resources, true, (UInt8 *)resource_path, sizeof(resource_path))) {
        if (resources) {
            CFRelease(resources);
        }
        capture_write("python: application resources are missing\n");
        return 127;
    }
    CFRelease(resources);
    char home_path[1100];
    snprintf(home_path, sizeof(home_path), "%s/python", resource_path);

    PyPreConfig preconfig;
    PyConfig config;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    PyStatus status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        capture_status("preinit failed", status);
        return 1;
    }
    PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0;
    config.buffered_stdio = 0;
    config.install_signal_handlers = 0;
    config.configure_c_stdio = 0;
    config.safe_path = 0;
    wchar_t *home = Py_DecodeLocale(home_path, NULL);
    status = PyConfig_SetString(&config, &config.home, home);
    PyMem_RawFree(home);
    if (PyStatus_Exception(status)) {
        capture_status("home failed", status);
        PyConfig_Clear(&config);
        return 1;
    }
    status = PyConfig_Read(&config);
    if (PyStatus_Exception(status)) {
        capture_status("stdlib path failed", status);
        PyConfig_Clear(&config);
        return 1;
    }
    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        capture_status("init failed", status);
        return 1;
    }
    const char *user_home = getenv("HOME");
    if (user_home && user_home[0]) {
        PyRun_SimpleString(
            "import os, traceback\n"
            "try:\n"
            "    site = os.path.join(os.environ.get('HOME', ''), 'Library', 'lib', 'python3.13', 'site-packages')\n"
            "    marker = os.path.join(site, 'pip')\n"
            "    if site and not os.path.isdir(marker):\n"
            "        import ensurepip, zipfile\n"
            "        from pathlib import Path\n"
            "        bundled = Path(ensurepip.__file__).parent / '_bundled'\n"
            "        wheels = sorted(bundled.glob('pip-*.whl'))\n"
            "        if not wheels:\n"
            "            raise RuntimeError('bundled pip wheel is missing')\n"
            "        os.makedirs(site, exist_ok=True)\n"
            "        with zipfile.ZipFile(wheels[-1]) as archive:\n"
            "            archive.extractall(site)\n"
            "except Exception:\n"
            "    path = os.environ.get('PTERM_PY_CAPTURE')\n"
            "    if path:\n"
            "        with open(path, 'a', encoding='utf-8') as handle:\n"
            "            handle.write(traceback.format_exc())\n");
        PyErr_Clear();
        char site[1200];
        snprintf(site, sizeof(site), "%s/Library/lib/python3.13/site-packages", user_home);
        PyObject *site_module = PyImport_ImportModule("site");
        if (site_module) {
            PyObject *add = PyObject_GetAttrString(site_module, "addsitedir");
            if (add) {
                PyObject *path = PyUnicode_FromString(site);
                PyObject *args = Py_BuildValue("(O)", path);
                PyObject *result = PyObject_CallObject(add, args);
                Py_XDECREF(result);
                Py_XDECREF(args);
                Py_XDECREF(path);
                Py_DECREF(add);
            }
            Py_DECREF(site_module);
            PyErr_Clear();
        }
    }
    return 0;
}

static int finish_python_error(void) {
    if (!PyErr_Occurred()) {
        return 0;
    }
    if (!PyErr_ExceptionMatches(PyExc_SystemExit)) {
        PyErr_Print();
        return 1;
    }
    PyObject *type = NULL;
    PyObject *value = NULL;
    PyObject *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);
    int code = 0;
    PyObject *status = value ? PyObject_GetAttrString(value, "code") : NULL;
    if (status && status != Py_None) {
        if (PyLong_Check(status)) {
            code = (int)PyLong_AsLong(status);
        } else {
            PyObject *text = PyObject_Str(status);
            const char *message = text ? PyUnicode_AsUTF8(text) : NULL;
            if (message && message[0]) {
                capture_write(message);
                capture_write("\n");
            }
            Py_XDECREF(text);
            code = 1;
        }
    }
    Py_XDECREF(status);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    return code < 0 ? 1 : code;
}

static int run_code(const char *source) {
    PyObject *main_module = PyImport_AddModule("__main__");
    if (!main_module) {
        return finish_python_error();
    }
    PyObject *globals = PyModule_GetDict(main_module);
    PyObject *result = PyRun_String(source, Py_file_input, globals, globals);
    if (result) {
        Py_DECREF(result);
        return 0;
    }
    return finish_python_error();
}

static void set_argv(int count, char **values) {
    PyObject *sys = PyImport_ImportModule("sys");
    if (!sys) {
        PyErr_Clear();
        return;
    }
    PyObject *list = PyList_New(count);
    for (int index = 0; index < count; index++) {
        PyList_SET_ITEM(list, index, PyUnicode_FromString(values[index] ? values[index] : ""));
    }
    PyObject_SetAttrString(sys, "argv", list);
    Py_DECREF(list);
    Py_DECREF(sys);
}

static int run_module(const char *module, int argc, char **argv) {
    set_argv(argc, argv);
    PyObject *runpy = PyImport_ImportModule("runpy");
    if (!runpy) {
        return finish_python_error();
    }
    PyObject *function = PyObject_GetAttrString(runpy, "run_module");
    Py_DECREF(runpy);
    if (!function) {
        return finish_python_error();
    }
    PyObject *args = Py_BuildValue("(s)", module);
    PyObject *kwargs = Py_BuildValue("{s:s,s:O}", "run_name", "__main__", "alter_sys", Py_True);
    PyObject *result = PyObject_Call(function, args, kwargs);
    Py_DECREF(function);
    Py_DECREF(args);
    Py_DECREF(kwargs);
    if (!result) {
        return finish_python_error();
    }
    Py_DECREF(result);
    return 0;
}

static int run_file(const char *filename, int argc, char **argv) {
    set_argv(argc, argv);
    FILE *file = fopen(filename, "rb");
    if (!file) {
        capture_write("python: cannot open script\n");
        return 1;
    }
    PyObject *main_module = PyImport_AddModule("__main__");
    PyObject *globals = main_module ? PyModule_GetDict(main_module) : NULL;
    PyObject *result = globals ? PyRun_File(file, filename, Py_file_input, globals, globals) : NULL;
    fclose(file);
    if (result) {
        Py_DECREF(result);
        return 0;
    }
    return finish_python_error();
}

static int python_main(int argc, char **argv) {
    int ready = ensure_python();
    if (ready != 0) {
        return ready;
    }
    PyObject *stream = NULL;
    if (install_capture(&stream) != 0) {
        capture_write("python: cannot capture output\n");
        PyErr_Clear();
        return 1;
    }
    int code = 0;
    if (argc >= 3 && strcmp(argv[1], "-c") == 0) {
        char *source = argv[2];
        char *program_argv[64];
        int program_count = argc - 2;
        if (program_count > 64) {
            program_count = 64;
        }
        program_argv[0] = "-c";
        for (int index = 3; index < argc && index - 2 < 64; index++) {
            program_argv[index - 2] = argv[index];
        }
        set_argv(program_count, program_argv);
        code = run_code(source);
    } else if (argc >= 3 && strcmp(argv[1], "-m") == 0) {
        code = run_module(argv[2], argc - 2, argv + 2);
    } else if (argc >= 2 && argv[1][0] != '-') {
        code = run_file(argv[1], argc - 1, argv + 1);
    } else {
        code = run_code("import sys\nprint('Python', sys.version)");
    }
    publish_capture(stream);
    Py_DECREF(stream);
    return code;
}

int pad_python3_main(int argc, const char * const *argv) {
    return python_main(argc, (char **)argv);
}

int pad_python3_ready(void) {
    return 1;
}

#else

int pad_python3_main(int argc, const char * const *argv) {
    (void)argc;
    (void)argv;
    return 127;
}

int pad_python3_ready(void) {
    return 0;
}

#endif
