JAR=unexpectedness-1.0.jar
sourcedir=$(pwd) 
count=$(\ls -1 ./$JAR 2>/dev/null | wc -l)

if (( count == 0 )); then
	echo "WARNING: no $JAR jar file."
else
	export CLASSPATH=$(ls -1 $sourcedir/$JAR | tail -n 1):$CLASSPATH
fi

export CLASSPATH=$CLASSPATH:$(\ls -1 $sourcedir/jars/runtime/*.jar | paste -d: -s -)
