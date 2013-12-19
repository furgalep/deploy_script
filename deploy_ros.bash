#!/bin/bash

# Thomas Schneider, 26/10/2013

##############################
# CONFIG                     #
##############################

#temporary base folder
TEMP_DIR_BASE="/tmp/deploy_iic"


##############################
# Parse args and load config #
##############################
#parse args
GIT_CONF_FILE=$1
ROS_CONF_FILE=$2
EXCLUDE_FILE=$3
KEEP_FILE=$4
STACK_FILE=$5
GIT_DEST=$6

#check if args are provided
if [ -z "$GIT_CONF_FILE" ] || [ -z "$ROS_CONF_FILE" ] || [ -z "$EXCLUDE_FILE" ] || [ -z "$STACK_FILE" ] || [ -z "$GIT_DEST" ] || [ -z "$KEEP_FILE" ] 
  then
    echo 
    echo -e "Usage: deploy_ros  GIT_SRC_LIST  ROS_PKG_FILE  EXCLUDE_FILE KEEP_FILE  STACK_CPY_FILE  DEPLOY_REPO_URL\n"
    echo -e "   This tool allows to download several git repositories (upstream), copy "
    echo -e "   ROS packages from these source repos to update another deployment git"
    echo -e "   repository with the changes."
    echo
    echo -e "   GIT_SRC_LIST:    File that contains a list of the source repos."
    echo -e "                      Format: GIT_URL_1, Branch/Tag"
    echo -e "                                  ...              "
    echo -e "                              GIT_URL_n, Branch/Tag"
    echo
    echo -e "   ROS_PKG_FILE:    File with line-separated list of ROS packages"
    echo -e "                    to copy from upstream to deployment repo."
    echo -e "                      Format: ROS_PKG_1"
    echo -e "                                 ...   "
    echo -e "                              ROS_PKG_n"
    echo
    echo -e "                    WARNING: Ros packages are detected using the manifest.xml"
    echo -e "                             might/will not work with Catkin!"
    echo
    echo -e "   EXCLUDE_FILE:    Line separated list of file patterns to exclude"
    echo -e "                    from copying (upstream->deployment)"
    echo -e "                      Ex: .git"
    echo -e "                           ...   "
    echo -e "                          *.bag"
    echo
    echo -e "   KEEP_FILE:       Line separated list of files to exclude from updating."
    echo -e "                    the file already on the deployment repo will be kept."
    echo -e "                      Ex: README"
    echo -e "                           ...   "
    echo -e "                          .gitignore"
    echo
    echo -e "   STACK_CPY_FILE:  Line separated list of files that should be copied along"
    echo -e "                    with the stack.xml. If a package specified in ROS_PKG_FILE"
    echo -e "                    is part of a stack, the stack.xml will be copied aswell."
    echo -e "                    Further you can set in this file what files from the ROS"
    echo -e "                    stack (non ROS packages) you want to copy aswell."
    echo -e "                    E.g. a folder for cmake find-scripts"
    echo

    exit 10
fi

#check if config files exist
if [ ! -f $GIT_CONF_FILE ]; then echo "Git config file not found: $GIT_CONF_FILE"; exit 10; fi
if [ ! -f $ROS_CONF_FILE ]; then echo "Ros config file not found: $ROS_CONF_FILE"; exit 10; fi
if [ ! -f $EXCLUDE_FILE ]; then echo "Copy exclude config file not found: $EXCLUDE_FILE"; exit 10; fi
if [ ! -f $KEEP_FILE ]; then echo "Deployment update exclude file (keep file) not found: $KEEP_FILE"; exit 10; fi
if [ ! -f $STACK_FILE ]; then echo "Stack copy config file not found: $STACK_FILE"; exit 10; fi

#load git configuration (format url,(tag or branch) )
GIT_SRC_LIST=()
GIT_BRANCH_LIST=()

while IFS=, read col1 col2
do
  #if lines are not empty
  if [ -n "$col1" ] || [ -n "$col2" ]
    then  
      #trim trailing/leading spaces
      col1=$(echo $col1 | tr -d ' ')
      col2=$(echo $col2 | tr -d ' ')

      #stores values in array
      GIT_SRC_LIST+=($col1)
      GIT_BRANCH_LIST+=($col2)
  fi
done < $GIT_CONF_FILE

#GIT_SRC_LIST=()                                                       #CHANGE HERE

#load ros package configuration (format ros_package_name )
ROS_PKG_COPY_LIST=()

while IFS=, read col1
do
  #if lines are not empty
  if [ -n "$col1" ]
    then  
      #trim trailing/leading spaces
      col1=$(echo $col1 | tr -d ' ')

      #stores values in array
      ROS_PKG_COPY_LIST+=($col1)
  fi
done < $ROS_CONF_FILE

#load copy exclude configuration ( rsync params )
COPY_EXCLUDE=()

while IFS=, read col1
do
  #if lines are not empty
  if [ -n "$col1" ]
    then  
      #trim trailing/leading spaces
      col1=$(echo $col1 | tr -d ' ')

      #stores values in array
      COPY_EXCLUDE+=($col1)
  fi
done < $EXCLUDE_FILE


#load copy exclude configuration ( rsync params )
KEEP_LIST=()

while IFS=, read col1
do
  #if lines are not empty
  if [ -n "$col1" ]
    then  
      #trim trailing/leading spaces
      col1=$(echo $col1 | tr -d ' ')

      #stores values in array
      KEEP_LIST+=($col1)
  fi
done < $KEEP_FILE


#load copy exclude configuration ( rsync params )
STACK_CPY=()

while IFS=, read col1
do
  #if lines are not empty
  if [ -n "$col1" ]
    then  
      #trim trailing/leading spaces
      col1=$(echo $col1 | tr -d ' ')

      #stores values in array

      STACK_CPY+=($col1)
  fi
done < $STACK_FILE


##############################
# Handle git login           #
##############################
git config --global credential.helper cache


##############################
# Create temp folders        #
##############################
#create temp folder + subfolder with random number...
TEMP_DIR=$TEMP_DIR_BASE"/"$RANDOM                                       #CHANGE HERE
mkdir -p $TEMP_DIR

#upstream source folder
TEMP_DIR_UPSTREAM=$TEMP_DIR"/upstream"
mkdir -p $TEMP_DIR_UPSTREAM

#downstream source folder
TEMP_DIR_DOWNSTREAM=$TEMP_DIR"/downstream"
mkdir -p $TEMP_DIR_DOWNSTREAM

#deploy repo folder
TEMP_DIR_DEPLOY=$TEMP_DIR"/deploy"
mkdir -p $TEMP_DIR_DEPLOY

#create logfile
LOG_FILE=$TEMP_DIR/"deploy.log"
touch $LOG_FILE

##############################
# Define some constants      #
##############################
COLOR_RED=$(tput setaf 1)
COLOR_BLUE=$(tput setaf 4)
COLOR_GREEN=$(tput setaf 2)
COLOR_END=$(tput sgr0)

##############################
# Get the sources            #
##############################
cd $TEMP_DIR_UPSTREAM

#clone all repos
echo "Cloning source git repos..."

for idx in "${!GIT_SRC_LIST[@]}"
do
  repo_url=${GIT_SRC_LIST[$idx]}
  repo_branch=${GIT_BRANCH_LIST[$idx]}

  #console output
  echo -en "\r  [$COLOR_BLUE FETCH $COLOR_END] $repo_url, $repo_branch"

  #check for login, if not ask pw
  echo
  LOG=$( git ls-remote ${GIT_SRC_LIST[idx]} )
  echo $LOG >> $LOG_FILE
  tput cuu 1;

  #repair formatting if asked for pw  
  if [[ $LOG != *refs* ]]
    then
      echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] $repo_url, $repo_branch"
      echo "Auth failed! See log file: $LOG_FILE!"
      exit 2
  fi

  #clone all repos  
  script -e -q -c "git clone -b $repo_branch $repo_url" /dev/null >> $LOG_FILE
  GIT_EXIT_CODE=$?

  echo "\n" >> $LOG_FILE

  #check git exit codes for success
  if [ $GIT_EXIT_CODE -ne 0 ]
    then
      echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] $repo_url, $repo_branch"

      echo -e "\n Check log file for information at $LOG_FILE"
      exit 2
    else
      echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] $repo_url, $repo_branch"
  fi
done


###############################
# Find the spec. ROS packages #
###############################
echo "Look for specified ROS packages..."

#variable that holds the path to the ROS pkgs that will be copied
ROS_PKG_DIR_LIST=()
PACKGE_NOT_FOUND=0

for ros_pkg in "${ROS_PKG_COPY_LIST[@]}"
do

  #find directory in which the ros pkg is stored
  pkg_dir_count=$(find $TEMP_DIR_UPSTREAM | grep "$ros_pkg/manifest.xml" | wc -l)

  if [ $pkg_dir_count -gt 1 ]
    then
      #Ros package name not unique
      pkg_dirs=$(find $TEMP_DIR_UPSTREAM | grep "$ros_pkg/manifest.xml" | tr '\n' ",")

      echo -e "\r\033[K  [$COLOR_RED NOT UNIQUE $COLOR_END] $ros_pkg: $pkg_dirs"
      PACKGE_NOT_FOUND=1
  elif [ $pkg_dir_count -lt 1 ]
    then
      #Ros package not found
      echo -e "\r\033[K  [$COLOR_RED NOT FOUND $COLOR_END] $ros_pkg"
      PACKGE_NOT_FOUND=1
  else
      # We found a unique ros pkg with the given name...
      pkg_dir=$(dirname $(find $TEMP_DIR_UPSTREAM | grep "$ros_pkg/manifest.xml") )
      echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] $ros_pkg: $pkg_dir"

      #store in list
      ROS_PKG_DIR_LIST+=($pkg_dir)
  fi
done


#exit if we didnt find one package or one is not unique
if [ $PACKGE_NOT_FOUND -eq 1 ]
  then
    echo -e "\n Check specified ROS package list!"
    exit 2
fi


################################
# Copy the needed ROS packages #
################################
echo "Copying found ROS packages..."

#build the copy exclude list
EXCLUDE=()
for exclude_elem in "${COPY_EXCLUDE[@]}"
do
  EXCLUDE+=" --exclude='$exclude_elem' "
done

#copy each package using rsync (easy exclude handling)
for ros_pkg_dir in "${ROS_PKG_DIR_LIST[@]}"
  do
    DO_EXIT=0

    #get the destination
    dest_dir=${ros_pkg_dir/$TEMP_DIR_UPSTREAM/$TEMP_DIR_DOWNSTREAM}
    
    #execute the pacakge copy
    mkdir -p $dest_dir
    COPY_CMD="rsync -av $EXCLUDE $ros_pkg_dir/ $dest_dir"

    echo $COPY_CMD >> $LOG_FILE
    script -e -q -c "$COPY_CMD" /dev/null >> $LOG_FILE

    if [ $? -ne 0 ]
      then
        # Copy failed
        pkg_dirs=$(find $TEMP_DIR_UPSTREAM | grep "$ros_pkg/manifest.xml" | tr '\n' ",")

        echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] $ros_pkg_dir"
        DO_EXIT=1
    else
        # Copy success
        echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] $ros_pkg_dir"
    fi

  #exit if we didnt find one package or one is not unique
  if [ $DO_EXIT -eq 1 ]
    then
      echo -e "\n Copying failed... Check log file at $LOG_FILE"
      exit 2
  fi

done

################################
# Copy parent stack files      #
################################
#check each package if it has a stack.xml in the folder one lvl above, if so copy the stack.xml downstream and also all files specifed (if it exists) in the input file STACK



for ros_pkg_dir in "${ROS_PKG_DIR_LIST[@]}"
do
  #check if package is in a stack
  LOG=$(ls $ros_pkg_dir/.. | grep stack.xml)


  if [ $LOG = "stack.xml" ]
    then
    
    #get the src/dst folders
    dest_dir_stack=${ros_pkg_dir/$TEMP_DIR_UPSTREAM/$TEMP_DIR_DOWNSTREAM}"/../"
    src_dir_stack="$ros_pkg_dir/.."

    #always copy stack.xml
    LOG=$( cp -R $src_dir_stack"/"stack.xml $dest_dir_stack)
    echo $LOG >> $LOG_FILE

    #copy all files specified in stack file
    for cpy_file in "${STACK_CPY[@]}"
    do
      #file to copy with path
      file=$src_dir_stack"/"$cpy_file

      #copy if file exists
      if [ -f $file ];
        then
          LOG=$( cp -R $file $dest_dir_stack)
          echo $LOG >> $LOG_FILE
        fi

      #copy if directory exists
      if [ -d $file ];
        then
          LOG=$( cp -R $file $dest_dir_stack)
          echo $LOG >> $LOG_FILE
        fi
    done
  fi
done



###############################
# Deploy to new git repo      #
###############################
echo "Deploying to repo..."
cd $TEMP_DIR_DEPLOY

#clone deployment repo
echo -en "\r  [$COLOR_BLUE FETCH $COLOR_END] Cloning into deployment repo: $GIT_DEST"


#check for login, if not ask pw
echo
LOG=$( git ls-remote $GIT_DEST )
echo $LOG
echo $LOG >> $LOG_FILE
tput cuu 1;

#check if pw ok
if [[ $LOG != *refs* ]]
  then
    echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] $repo_url, $repo_branch"
    echo -e "\nEither the git auth failed or this is your initial commit! (See log file: $LOG_FILE)\n\nIf this is your initial commit: Switch to the directory $TEMP_DIR_DEPLOY and do the initial commit/push manually with: \n\t cd $TEMP_DIR_DOWNSTREAM \n\t git init \n\t git remote add origin $GIT_DEST \n\t git add -A \n\t git commit -m \"initial commit\" \n\t git push origin master "
    exit 2
fi

script -e -c "git clone $GIT_DEST ." /dev/null >> $LOG_FILE
GIT_EXIT_CODE=$?
echo "\n" >> $LOG_FILE

if [ $GIT_EXIT_CODE -ne 0 ]
  then
    echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] Cloning into deployment repo: $GIT_DEST"

    echo -e "\n Check log file for information at $LOG_FILE"
    exit 2   
  else
    echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] Cloning into deployment repo: $GIT_DEST"
fi

#copy .git (tracking) to downstream source folder
cp -R $TEMP_DIR_DEPLOY"/.git" $TEMP_DIR_DOWNSTREAM
cd $TEMP_DIR_DOWNSTREAM


#copy the files which should not be updated according to user input list, from the online deployment repo to local downstream repo, so it doesnt get deleted with the "git add -A"
for file in "${KEEP_LIST[@]}"
do
  #if file or directory exists
  path_file=$TEMP_DIR_DEPLOY/$file
  
  if [ -d $path_file ] || [ -f $path_file ] 
  then
    LOG=$( cp -R $path_file $TEMP_DIR_DOWNSTREAM/$file )
    echo $LOG >> $LOG_FILE
  fi
done


#git add all files
echo -en "\r  [$COLOR_BLUE WORKING $COLOR_END] Adding new files to deployment repo"

script -e -c "git add -f -A" /dev/null >> $LOG_FILE
GIT_EXIT_CODE=$?

echo "\n" >> $LOG_FILE

if [ $GIT_EXIT_CODE -ne 0 ]
  then
    echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] Adding new files to deployment repo"

    echo -e "\n Check log file for information at $LOG_FILE"
    exit 2     
  else
    echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] Adding new files to deployment repo"
fi

#git commit all files
COMMIT_MSG="update to new version"

echo -en "\r  [$COLOR_BLUE WORKING $COLOR_END] Commiting changes in deployment repo "

COMMIT_LOG=$(script -e -c "git commit -m '$COMMIT_MSG'" /dev/null)
echo $COMMIT_LOG >> $LOG_FILE
GIT_EXIT_CODE=$?

echo "\n" >> $LOG_FILE
if [ $GIT_EXIT_CODE -ne 0 ]
  then
    echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] Commiting changes in deployment repo "

    echo -e "\n Check log file for information at $LOG_FILE"
    exit 2      
  else
    echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] Commiting changes in deployment repo "
fi

#only ask for push if there are changes

if [[ $COMMIT_LOG != *"nothing to commit"* ]]
  then

    #show changes all repo changes
    echo
    read -p "Show commit file changes? [y/N] " -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo -n "$COMMIT_LOG" | less
    fi

    #git push all files
    read -p "Push to the deployment repo? [y/N] " -n 1 -r

    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
      echo
      echo -en "\r  [$COLOR_BLUE WORKING $COLOR_END] Pushing changes to deployment repo "

      script -e -c "git push origin master" /dev/null  >> $LOG_FILE
      GIT_EXIT_CODE=$?

      echo "\n" >> $LOG_FILE
      if [ $GIT_EXIT_CODE -ne 0 ]
        then
          echo -e "\r\033[K  [$COLOR_RED FAIL $COLOR_END] Pushing changes to deployment repo "

          echo -e "\n Check log file for information at $LOG_FILE"
          exit 2  
        else
          echo -e "\r\033[K  [$COLOR_GREEN OK $COLOR_END] Pushing changes to deployment repo "
      fi
    fi
  
  else
    echo -e "\r\033[K  [$COLOR_RED NO CHANGES $COLOR_END] Pushing changes to deployment repo "
fi

echo
echo "Deployment repository located at: $TEMP_DIR_DOWNSTREAM"
echo

###############################
# Clean up                    #
###############################

#delete tmp folder


exit 0




