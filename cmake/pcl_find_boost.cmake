# Find and set Boost flags

# Option to allow fallback to shared libraries if static are not available
# Set to OFF to require static libraries (will fail if not found)
option(PCL_BOOST_ALLOW_SHARED_FALLBACK "Allow fallback to shared Boost libraries if static are not available" OFF)

# If we would like to compile against a dynamically linked Boost
if(PCL_BUILD_WITH_BOOST_DYNAMIC_LINKING_WIN32 AND WIN32)
  set(Boost_USE_STATIC_LIBS OFF)
  set(Boost_USE_STATIC OFF)
  set(Boost_USE_MULTITHREAD ON)
  string(APPEND CMAKE_CXX_FLAGS " -DBOOST_ALL_DYN_LINK -DBOOST_ALL_NO_LIB")
else()
  # Try to use static linking for Boost first
  # MODULE mode respects Boost_USE_STATIC_LIBS better than CONFIG mode
  set(Boost_USE_STATIC_LIBS ON)
  set(Boost_USE_STATIC ON)
  set(Boost_USE_MULTITHREAD ON)
endif()

if(CMAKE_CXX_STANDARD MATCHES "14")
  # Optional boost modules
  set(BOOST_OPTIONAL_MODULES serialization mpi system)
  # Required boost modules
  set(BOOST_REQUIRED_MODULES filesystem iostreams)
else()
  # Optional boost modules
  set(BOOST_OPTIONAL_MODULES filesystem serialization mpi system)
  # Required boost modules
  set(BOOST_REQUIRED_MODULES iostreams)
endif()

# Determine Boost root directory
if(Boost_ROOT)
  set(_boost_root ${Boost_ROOT})
elseif(BOOST_ROOT)
  set(_boost_root ${BOOST_ROOT})
else()
  set(_boost_root "")
endif()

# If Boost_ROOT is set and we want static libraries, verify static libs exist and configure paths
if(_boost_root AND Boost_USE_STATIC_LIBS)
  set(_boost_static_libs_exist TRUE)
  foreach(_component ${BOOST_REQUIRED_MODULES})
    if(NOT EXISTS "${_boost_root}/lib/libboost_${_component}.a")
      set(_boost_static_libs_exist FALSE)
      break()
    endif()
  endforeach()
  
  if(_boost_static_libs_exist)
    message(STATUS "Static Boost libraries found in ${_boost_root}/lib")
    # Clear any cached Boost findings to force re-search
    unset(Boost_FOUND CACHE)
    unset(Boost_LIBRARIES CACHE)
    # Prevent FindBoost from searching system paths
    set(Boost_NO_SYSTEM_PATHS ON CACHE BOOL "Don't search system paths for Boost" FORCE)
    set(Boost_ADDITIONAL_VERSIONS "1.89" "1.89.0")
    # Ensure Boost_ROOT is set for find_package (FindBoost uses this automatically)
    if(NOT Boost_ROOT)
      set(Boost_ROOT ${_boost_root} CACHE PATH "Boost root directory" FORCE)
    endif()
    # Also set BOOST_ROOT for compatibility
    if(NOT BOOST_ROOT)
      set(BOOST_ROOT ${_boost_root} CACHE PATH "Boost root directory (alternative)" FORCE)
    endif()
  endif()
endif()

# Try MODULE mode first - it respects Boost_USE_STATIC_LIBS better
# FindBoost module automatically uses Boost_ROOT when set
find_package(Boost 1.71.0 QUIET COMPONENTS ${BOOST_OPTIONAL_MODULES})
find_package(Boost 1.71.0 QUIET COMPONENTS ${BOOST_REQUIRED_MODULES})

# If MODULE mode didn't work but we have Boost_ROOT with static libs, try CONFIG mode
if(NOT Boost_FOUND AND _boost_root AND _boost_static_libs_exist)
  message(STATUS "MODULE mode failed, trying CONFIG mode for Boost...")
  # CONFIG mode works better with explicit paths
  find_package(Boost 1.71.0 QUIET COMPONENTS ${BOOST_OPTIONAL_MODULES} CONFIG
               PATHS ${_boost_root} ${_boost_root}/lib/cmake NO_DEFAULT_PATH)
  find_package(Boost 1.71.0 QUIET COMPONENTS ${BOOST_REQUIRED_MODULES} CONFIG
               PATHS ${_boost_root} ${_boost_root}/lib/cmake NO_DEFAULT_PATH)
endif()

# If static libraries weren't found, handle according to fallback option
if(NOT Boost_FOUND AND Boost_USE_STATIC_LIBS)
  if(PCL_BOOST_ALLOW_SHARED_FALLBACK)
    message(WARNING "Static Boost libraries not found. Falling back to shared libraries.")
    message(WARNING "To use static linking, build Boost from source with static libraries enabled.")
    set(Boost_USE_STATIC_LIBS OFF)
    set(Boost_USE_STATIC OFF)
    # Clear the cache to force re-search
    unset(Boost_FOUND CACHE)
    unset(Boost_LIBRARIES CACHE)
    foreach(component ${BOOST_OPTIONAL_MODULES} ${BOOST_REQUIRED_MODULES})
      unset(Boost_${component}_LIBRARY CACHE)
      unset(Boost_${component}_LIBRARY_DEBUG CACHE)
      unset(Boost_${component}_LIBRARY_RELEASE CACHE)
    endforeach()
    # Try again with shared libraries
    find_package(Boost 1.71.0 QUIET COMPONENTS ${BOOST_OPTIONAL_MODULES})
    find_package(Boost 1.71.0 REQUIRED COMPONENTS ${BOOST_REQUIRED_MODULES})
  else()
    message(FATAL_ERROR "\n"
                         "=============================================================================\n"
                         "Static Boost libraries not found!\n"
                         "=============================================================================\n"
                         "Since openSUSE doesn't provide static Boost libraries, you need to build\n"
                         "Boost from source with static libraries enabled.\n\n"
                         "A build script has been provided. To build Boost with static libraries:\n\n"
                         "  1. Navigate to the PCL source directory\n"
                         "  2. Run: ./build_boost_static.sh\n"
                         "  3. Configure CMake with: -DBoost_ROOT=\$HOME/local/boost-1.89.0-static\n\n"
                         "Then configure CMake with:\n"
                         "  cmake -DBoost_ROOT=\$HOME/local/boost-1.89.0-static ...\n\n"
                         "Alternatively, set PCL_BOOST_ALLOW_SHARED_FALLBACK=ON to allow fallback\n"
                         "to shared libraries (not recommended if you need static linking).\n"
                         "=============================================================================")
  endif()
endif()

if(Boost_FOUND)
  set(BOOST_FOUND TRUE)
  
  # Always ensure required targets exist, creating them if needed
  # This handles both MODULE mode (which doesn't create targets) and
  # CONFIG mode cases where targets might not be created correctly
  set(_need_to_create_targets FALSE)
  
  # Check if required targets exist
  foreach(_component ${BOOST_REQUIRED_MODULES})
    if(NOT TARGET Boost::${_component})
      set(_need_to_create_targets TRUE)
      break()
    endif()
  endforeach()
  
  # If targets don't exist, create them manually
  if(_need_to_create_targets)
    message(STATUS "Creating Boost imported targets manually")
    message(STATUS "Boost_ROOT: ${_boost_root}")
    message(STATUS "Boost_INCLUDE_DIRS: ${Boost_INCLUDE_DIRS}")
    message(STATUS "Boost_LIBRARY_DIRS: ${Boost_LIBRARY_DIRS}")
    
    # Create the main Boost::boost interface target
    if(NOT TARGET Boost::boost)
      add_library(Boost::boost INTERFACE IMPORTED)
      if(Boost_INCLUDE_DIRS)
        set_target_properties(Boost::boost PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIRS}")
      elseif(Boost_INCLUDE_DIR)
        set_target_properties(Boost::boost PROPERTIES
          INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIR}")
      endif()
    endif()
    
    # Create component targets - always check required modules first
    foreach(_component ${BOOST_REQUIRED_MODULES} ${BOOST_OPTIONAL_MODULES})
      # Skip if target already exists
      if(TARGET Boost::${_component})
        message(STATUS "Boost::${_component} target already exists")
        continue()
      endif()
      
      message(STATUS "Attempting to create Boost::${_component} target...")
      
      # Try to find the library file - check multiple sources
      set(_lib_path "")
      
      # First, try CMake variables set by find_package
      if(Boost_${_component}_LIBRARY_RELEASE)
        set(_lib_path "${Boost_${_component}_LIBRARY_RELEASE}")
      elseif(Boost_${_component}_LIBRARY)
        set(_lib_path "${Boost_${_component}_LIBRARY}")
      elseif(Boost_${_component}_LIBRARY_DEBUG)
        set(_lib_path "${Boost_${_component}_LIBRARY_DEBUG}")
      endif()
      
      # If still no path or path doesn't exist, search in known locations
      if(NOT _lib_path OR NOT EXISTS "${_lib_path}")
        # Determine library name and search
        set(_lib_name "libboost_${_component}")
        if(Boost_USE_STATIC_LIBS)
          set(_lib_name "${_lib_name}.a")
        else()
          set(_lib_name "${_lib_name}.so")
        endif()
        
        # Try Boost_LIBRARY_DIRS first
        if(Boost_LIBRARY_DIRS)
          foreach(_lib_dir ${Boost_LIBRARY_DIRS})
            if(EXISTS "${_lib_dir}/${_lib_name}")
              set(_lib_path "${_lib_dir}/${_lib_name}")
              break()
            endif()
          endforeach()
        endif()
        
        # Fallback to Boost_ROOT/lib (most reliable when Boost_ROOT is set)
        if((NOT _lib_path OR NOT EXISTS "${_lib_path}") AND _boost_root)
          if(EXISTS "${_boost_root}/lib/${_lib_name}")
            set(_lib_path "${_boost_root}/lib/${_lib_name}")
          endif()
        endif()
      endif()
      
      # Create target if we found the library
      if(_lib_path AND EXISTS "${_lib_path}")
        # Determine if it's a static or shared library
        get_filename_component(_lib_ext "${_lib_path}" EXT)
        if(_lib_ext STREQUAL ".a" OR _lib_ext STREQUAL ".lib")
          set(_lib_type STATIC)
        else()
          set(_lib_type SHARED)
        endif()
        
        # Create the imported target
        add_library(Boost::${_component} ${_lib_type} IMPORTED)
        set_target_properties(Boost::${_component} PROPERTIES
          IMPORTED_LOCATION "${_lib_path}")
        
        if(Boost_INCLUDE_DIRS)
          set_target_properties(Boost::${_component} PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIRS}")
        elseif(Boost_INCLUDE_DIR)
          set_target_properties(Boost::${_component} PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIR}")
        endif()
        
        # If we have both release and debug, set both
        if(Boost_${_component}_LIBRARY_RELEASE AND Boost_${_component}_LIBRARY_DEBUG)
          set_target_properties(Boost::${_component} PROPERTIES
            IMPORTED_LOCATION_RELEASE "${Boost_${_component}_LIBRARY_RELEASE}"
            IMPORTED_LOCATION_DEBUG "${Boost_${_component}_LIBRARY_DEBUG}")
        endif()
        
        message(STATUS "Created Boost::${_component} target -> ${_lib_path}")
      else()
        message(WARNING "Boost component ${_component} - library path not found")
        message(WARNING "  Searched for: ${_lib_name}")
        message(WARNING "  Boost_LIBRARY_DIRS: ${Boost_LIBRARY_DIRS}")
        message(WARNING "  _boost_root: ${_boost_root}")
        # For required modules, this is an error
        if(_component IN_LIST BOOST_REQUIRED_MODULES)
          message(FATAL_ERROR "Required Boost component ${_component} library not found!")
        endif()
      endif()
    endforeach()
  endif()
endif()
