#!/usr/bin/env zsh
############### INITIALIZATION ################################################
WIKIDUMP_XML=/vagrant/enwiki-20140203-pages-articles.xml
STOPWORDS=stopwords.txt
N_TOP_CATEGORIES=20000
SEED=1234567890

# The current directory should look like this:
# ./stopwords.txt                           # <---- stopwords, one per line
# ./dump
# /vagrant/enwiki-20140203-pages-articles.xml # <---- the wikipedia dump
# ./run-experiments.sh                      # <---- this script
# ./evaluation
# ./evaluation/pool.txt                     # <---- specifies which scorers should be evaluated
# ./evaluation/human-evaluation.tsv         # <---- the human-made dataset
# 
# Let us check this is true
for file in "stopwords.txt" "$WIKIDUMP_XML" "evaluation/pool.txt" "evaluation/human-evaluation.tsv"
do
	if [ ! -f $file ]; then
	    echo "File $file not found!"
	    exit 1
	fi
done

# Let's check java has been compiled and it is in the classpath
{ java efen.scorers.llamafur.LatentMatrixEstimator --help 2>&1 | grep -q "Could not find or load main class"; } && { echo 'Java LlamaFur commands not found. You should compile them and include them in the classpath. Look at the "Compile LlamaFur code" part of readme.md!' ; exit 1; }



############### PARSING WIKIPEDIA DUMP #########################################

# Generate page names, category names, page to category map, category pseudotree 
java efen.parsewiki.WikipediaCategoryProducer $WIKIDUMP_XML ./

# precomputation steps needed for the graph
mkdir resolvers
java it.unimi.di.big.mg4j.tool.URLMPHVirtualDocumentResolver -o pages.uris resolvers/enwiki.vdr
java efen.parsewiki.WikipediaDocumentSequence $WIKIDUMP_XML http://en.wikipedia.org/wiki/ pages.uris resolvers/enwiki.vdr resolvers/enwikired.vdr
# produce the actual graph
java efen.parsewiki.WikipediaGraphProducer $WIKIDUMP_XML resolvers/enwikired.vdr pages-with-selfloop
# remove self-loops from graph
java it.unimi.dsi.webgraph.Transform arcfilter pages-with-selfloop pages NO_LOOPS
rm pages-with-selfloop*

# Generate the Archive4j archive with textual data for text-based scorers
mkdir text-archive
cd text-archive
java efen.parsewiki.WikipediaTextArchiveProducer $WIKIDUMP_XML ../$STOPWORDS Archive
cat Archive.terms | java it.unimi.dsi.util.FrontCodedStringList Archive.termmap.inverted
cd ..





############### SELECTING TOP CATEGORIES #######################################
mkdir top-categories
cd top-categories
java efen.categories.CategorySelectionToolchain ../categoryPseudotree.graph ../page2cat.ser $N_TOP_CATEGORIES --names ../catId2Name.ser top -e "wiki" -e "categories" -e "main topic classifications" -e "template" -e "navigational box" --trim
cd ..



############### LEARNING LLAMAFUR MATRIX #######################################
mkdir llamafurmatrix
cd llamafurmatrix
java efen.scorers.llamafur.LatentMatrixEstimator ../top-categories/top-page2cat.ser ../pages.graph llamafur-w --seed 1234567890 -k 2 -m 20000 --savestats accuracy-recall.tsv
java efen.scorers.llamafur.NaiveMatrixEstimator ../top-categories/top-page2cat.ser ../pages.graph naive-llamafur-w.ser
cd ..

### computing stats
#cd evaluation
#java efen.scorers.ScorerStatisticsSummarizer "scorers.aa.AdamicAdarScorer(../pages)" AdamicAdar-stats.properties
#java efen.scorers.ScorerStatisticsSummarizer "scorers.textual.JacquenetM4Scorer(../pages, ../text-archive/Archive.archive)" JacquenetM4-stats.properties
#java efen.scorers.ScorerStatisticsSummarizer "scorers.llamafur.LlamaFurScorer(../pages, ../llamafurmatrix/llamafur-w-1.ser, ../top-categories/top-page2cat.ser, LlamaFur)" LlamaFur-stats.properties
#cd ..


############### EVALUATING RESULTS #############################################
cd evaluation
java efen.scorers.llamafur.classifier.evaluation.TestMatrix 200 10000 ../llamafurmatrix/llamafur-w-1.ser ../pages.graph ../top-categories/top-page2cat.ser 1 | tee >(grep -v INFO > test-matrix.txt)
java efen.evaluation.createdataset.PooledDatasetChecker pool.txt ../pageName2Id.ser human-evaluation.tsv | tee >(grep -v INFO > dataset-check.txt)
java efen.evaluation.measure.BPrefMeasure pool.txt human-evaluation.tsv ../pageName2Id.ser -o bprefs.tsv -n ../pageId2Name.ser | tee >(grep -v INFO > avg-bpref.txt)
java efen.evaluation.measure.PrecisionRecallPlot pool.txt human-evaluation.tsv ../pageName2Id.ser -o precision-recall.tsv -n ../pageId2Name.ser
java efen.analysis.ScorerComparison ../pageName2Id.ser human-evaluation.tsv llamafur-vs-human.tsv "scorers.llamafur.LlamaFurScorer(../pages, ../llamafurmatrix/llamafur-w-1.ser, ../top-categories/top-page2cat.ser, LlamaFur)"
cd ..

echo "Results available in directory 'evaluation'"
